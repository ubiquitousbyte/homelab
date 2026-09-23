# etcd operator runbook

Day-to-day checks and disaster recovery for the `cx3301`/`cx3302`/`cx3303`
etcd cluster. See [README.md](README.md) for how the cluster is built.

## Quick health check

```sh
uv run ansible etcd -m shell -a "etcdctl endpoint health --write-out=table"
uv run ansible etcd -m shell -a "etcdctl member list --write-out=table"
```

All three should say `true`/`started`. One member down still means a
healthy cluster (quorum needs 2 of 3).

Check DB size and who's leader:

```sh
uv run ansible cx3301 -m shell -a "etcdctl endpoint status --write-out=table"
```

## Trigger a snapshot or defrag by hand

Normally these run on their own timers (daily snapshot, weekly staggered
defrag). To run one immediately:

```sh
uv run ansible cx3301 -m shell -a "systemctl start etcd-snapshot.service"
uv run ansible cx3301 -m shell -a "systemctl start etcd-defrag.service"
```

Defrag blocks that member while it runs. Never trigger it on two members at
once.

---

## Case 1: one member is down, but comes back

A reboot, a crash, a network blip. The other two members still hold quorum,
so the cluster kept serving reads and writes the whole time.

Nothing to restore. Once the node is back:

```sh
uv run ansible-playbook playbooks/site.yml --limit cx3301
```

etcd starts back up, rejoins as the same member it already was, and raft
replication catches it up automatically from the other two. No snapshot
needed for this case.

## Case 2: one member is permanently lost (disk gone, box destroyed)

Quorum is still fine (2 of 3), but that member's identity needs to be
retired and replaced -- you can't just reuse its old data, because it no
longer exists.

```
  cx3301 (dead)        cx3302 (alive)       cx3303 (alive)
      X                     |                     |
      |                     +----------quorum------+
      |
   1. remove this member's identity from the cluster
   2. bring up a replacement server (same name, same private IP)
   3. add it back as a brand-new member
   4. start etcd on it pointed at the *existing* cluster
```

1. **Confirm quorum is intact** (2 of the 3 report healthy) before touching
   anything -- removing a member while quorum is already lost makes things
   worse.

2. **Rebuild the underlying server**, if it was destroyed. `tofu apply`
   recreates it under the same name/IP from `cx33.auto.tfvars` (a drop-in
   replacement), or restore it from Hetzner's whole-VM Backup (Case 4) if
   you'd rather get the exact box back.

3. **Run the replacement playbook**, which does the remove-old /
   add-new / start-with-`existing` sequence for you:
   ```sh
   uv run ansible-playbook playbooks/etcd-replace-member.yml \
     --limit cx3301 -e confirm=cx3301
   ```
   It refuses to run unless `confirm` matches the target host, and refuses
   to touch a member that's still reporting healthy -- see
   `playbooks/etcd-replace-member.yml` for the exact steps.

4. **Verify**: the playbook prints the final `etcdctl member list` output,
   which should show three `started` members again.

## Case 3: quorum is lost (2 or 3 members gone, or data corrupted)

The cluster can no longer make progress on its own. This is the only case
that needs an actual snapshot restore.

```
  Before:  cx3301 X    cx3302 X    cx3303 (alive, maybe)
                                          |
  Pick a snapshot -----> etcdutl snapshot restore -----> fresh data dir
                                          |
  Repeat on every member, same snapshot file, then start etcd on all three
```

1. **Find a snapshot.** Newest one per node is in `/var/lib/etcd-backups/`.
   If no node survived at all, restore that directory from Hetzner's
   whole-VM Backup first (Case 4), then use the snapshot inside it.

2. **Stop etcd everywhere it's still running:**
   ```sh
   uv run ansible etcd -m shell -a "systemctl stop etcd"
   ```

3. **Restore the snapshot into a fresh data directory, on each member,**
   using `etcdutl` (not `etcdctl` -- this works offline, no cluster needed):
   ```sh
   etcdutl snapshot restore /var/lib/etcd-backups/etcd-<timestamp>.db \
     --name cx3301 \
     --initial-cluster "cx3301=http://10.0.1.1:2380,cx3302=http://10.0.1.2:2380,cx3303=http://10.0.1.3:2380" \
     --initial-cluster-token homelab-etcd \
     --initial-advertise-peer-urls http://10.0.1.1:2380 \
     --data-dir /var/lib/etcd-restored
   ```
   Change `--name` and `--initial-advertise-peer-urls` per node; the rest
   stays identical on all three.

4. **Swap the restored directory into place:**
   ```sh
   rm -rf /var/lib/etcd
   mv /var/lib/etcd-restored /var/lib/etcd
   chown -R etcd:etcd /var/lib/etcd
   ```

5. **Start etcd on all three** (the unit already uses
   `--initial-cluster-state=new`, which is correct here -- restoring a
   snapshot always forms a new cluster incarnation seeded with the old
   data):
   ```sh
   uv run ansible etcd -m shell -a "systemctl start etcd"
   ```

6. **Verify**: `etcdctl member list` and `etcdctl endpoint health` both
   report all three as healthy, and spot-check that expected keys exist.

## Case 4: restoring a node from Hetzner's whole-VM Backup

Use this when you want the exact machine back (OS, Docker, etcd binary and
data, all of it) rather than just etcd's data. Hetzner Cloud console -> the
server -> Backups -> pick a date -> Rebuild from Backup, or create a new
server from that backup image.

After the rebuild finishes:

```sh
uv run ansible cx3301 -m ping   # confirm it's reachable again
```

If the node was still a recognized etcd member the whole time (you didn't
run `etcdctl member remove` on it), just starting etcd is enough -- raft
replication catches it up from the other two automatically, no manual
snapshot restore needed. If it *had* been removed, run the replacement
playbook from Case 2 instead.

---

## Known limitations

- **No TLS**, by design -- see [README.md](README.md#whats-deliberately-not-here).
