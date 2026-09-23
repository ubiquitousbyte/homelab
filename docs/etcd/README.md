# etcd cluster

A 3-node etcd cluster runs on `cx3301`, `cx3302`, and `cx3303`. `cx3304` is a
spare and does not run etcd.

## Topology

```
                    Hetzner private network (10.0.1.0/24)
   +------------------------------------------------------------------+
   |                                                                  |
   |   +-----------+     +-----------+     +-----------+   +--------+ |
   |   |  cx3301   |     |  cx3302   |     |  cx3303   |   | cx3304 | |
   |   | 10.0.1.1  |<--->| 10.0.1.2  |<--->| 10.0.1.3  |   |(spare) | |
   |   |           |<----+-----------+---->|           |   |        | |
   |   +-----+-----+     +-----+-----+     +-----+-----+   +--------+ |
   |         |                 |                 |                   |
   +---------|-----------------|-----------------|-------------------+
             |                 |                 |
        etcd peer :2380   etcd peer :2380   etcd peer :2380
        etcd client:2379  etcd client:2379  etcd client:2379
```

Each node talks to the other two over the private network, not the public
internet. No TLS: the private subnet is already firewalled off from the
world, so plain HTTP is fine here. Three members means the cluster keeps
working if any *one* node goes down, but not two.

## How it's built

Terraform decides *which* machines are etcd members. `cx33.auto.tfvars`
labels three of the four servers:

```hcl
cx3301 = { ip = "10.0.1.1", labels = { etcd = "member" }, backups = true }
cx3302 = { ip = "10.0.1.2", labels = { etcd = "member" }, backups = true }
cx3303 = { ip = "10.0.1.3", labels = { etcd = "member" }, backups = true }
cx3304 = { ip = "10.0.1.4" }
```

Ansible's inventory turns that label into a group automatically
(`inventory/hcloud.yml`):

```yaml
groups:
  etcd: hcloud_labels.etcd is defined and hcloud_labels.etcd == "member"
```

No host list is hardcoded anywhere. Add `labels = { etcd = "member" }` to a
fourth machine and it joins the group on the next Ansible run.

The `etcd` role (`roles/etcd/`) then does the actual install:

```
┌─────────────────────────────────────────────┐
│ 1. Create a dedicated "etcd" system user     │
│ 2. Download the pinned etcd release          │
│    (checksum-verified, from etcd-io/etcd)    │
│ 3. Install etcd, etcdctl, etcdutl            │
│ 4. Create /var/lib/etcd (data)               │
│ 5. Create /var/lib/etcd-backups (snapshots)  │
│ 6. Template + start the etcd systemd unit    │
│ 7. Template + start snapshot/defrag timers   │
└─────────────────────────────────────────────┘
```

Each node's systemd unit is generated from one template
(`roles/etcd/templates/etcd.service.j2`). It fills in that node's own private
IP and the full member list, so every node ends up with a correct,
self-describing unit -- no per-host files to maintain by hand.

## Why the private network needed a fix

Hetzner attaches a private-network card to each server, but its own
cloud-init image never brings that card up -- it's present but switched off.
This was found and fixed while first bringing etcd up: `roles/common/tasks/
private_network.yml` finds that card and turns on DHCP for it, so the node
gets the private IP Terraform reserved for it. Without this fix, etcd can't
bind to its private IP at all.

## Keeping the data from growing forever

etcd never deletes old data by itself unless told to. Two settings handle
that:

- **Auto-compaction** -- built into the `etcd.service.j2` unit
  (`--auto-compaction-retention=1h`). etcd throws away old versions of keys
  older than one hour, continuously, on its own.
- **Defrag** -- compaction leaves gaps in the on-disk file; defrag reclaims
  that space. This must happen to one member at a time, never all three at
  once, or the cluster loses quorum mid-defrag.

```
   Sunday, UTC
   00:00        03:00        04:00        05:00
     |            |            |            |
     |     cx3301 defrags      |            |
     |            |    cx3302 defrags       |
     |            |            |   cx3303 defrags
```

A systemd timer per node (`etcd-defrag.timer`) triggers this, staggered one
hour apart automatically -- each node's position in the sorted member list
decides its hour, so there's nothing to hardcode.

## Backups

Two independent layers, catching different kinds of failure:

```
 ┌───────────────────────────────┐   ┌────────────────────────────────┐
 │ etcd-native snapshot           │   │ Hetzner server Backups          │
 │ (etcdctl snapshot save)        │   │ (whole-disk, off-host)          │
 │                                 │   │                                  │
 │ - daily, per node               │   │ - daily, automatic              │
 │ - last 7 kept, older pruned     │   │ - 7 rotating copies              │
 │ - lives in                      │   │ - stored off the physical host  │
 │   /var/lib/etcd-backups         │   │ - covers the ENTIRE disk,       │
 │ - portable: can restore into    │   │   etcd snapshots included       │
 │   a brand new cluster           │   │ - restores the whole server     │
 └───────────────────────────────┘   └────────────────────────────────┘
        "I deleted the wrong key"         "this node's disk just died"
```

The etcd snapshot is application-aware and portable -- it can be restored
into any etcd cluster, not just this exact server. Hetzner's Backup is
whole-machine and off-host -- it protects against losing the entire node,
and it automatically picks up the local etcd snapshot files too, since
they live on the same disk it backs up. Neither replaces the other.

Snapshot timing, same stagger idea as defrag but simpler (all nodes can
snapshot independently, since it doesn't block anything):

```
   Every day, 00:00 UTC
   cx3301 --> snapshot --> prune anything past the newest 7
   cx3302 --> snapshot --> prune anything past the newest 7
   cx3303 --> snapshot --> prune anything past the newest 7
```

## Operating it

Check cluster health from any member:

```sh
ansible etcd -m shell -a "etcdctl endpoint health --write-out=table"
ansible etcd -m shell -a "etcdctl member list --write-out=table"
```

Check the timers are scheduled:

```sh
ansible etcd -m shell -a "systemctl list-timers etcd-snapshot.timer etcd-defrag.timer"
```

Trigger a snapshot by hand instead of waiting for the timer:

```sh
ansible cx3301 -m shell -a "systemctl start etcd-snapshot.service"
```

Restore from a snapshot (disaster recovery) uses `etcdutl snapshot restore`,
not `etcdctl` -- `etcdutl` works offline, directly on the snapshot file,
without a running cluster.

## What's deliberately not here

- **No TLS.** Traffic never leaves the private subnet, which is already
  closed to the internet.
- **No off-node snapshot shipping between nodes.** Hetzner's Backup feature
  already gets the snapshots off-host; adding node-to-node transfer would
  mean managing a new SSH keypair between servers for no real benefit.
- **No dedicated disk for etcd.** The `cx33` root disk is already local
  NVMe. Hetzner's only attachable "extra disk" is network-attached and
  noticeably slower -- worse for etcd's fsync-sensitive writes, not better.
