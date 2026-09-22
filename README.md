# homelab

Infrastructure-as-code for my homelab. Provisions servers on [Hetzner Cloud](https://www.hetzner.com/cloud/) with [OpenTofu](https://opentofu.org/) and configures them using [Ansible](https://docs.ansible.com/).

## Architecture

```
                        Hetzner Cloud (nbg1)
  +---------------------------------------------------------------------+
  |                                                                     |
  |              Network: "main" (10.0.0.0/16)                          |
  |  +---------------------------------------------------------------+  |
  |  |                                                               |  |
  |  |           Subnet: "cloud01" (10.0.1.0/24, eu-central)        |  |
  |  |                                                               |  |
  |  |   +------------+  +------------+  +------------+  +--------+  |  |
  |  |   |   cx3301   |  |   cx3302   |  |   cx3303   |  | cx3304 |  |  |
  |  |   | 10.0.1.1   |  | 10.0.1.2   |  | 10.0.1.3   |  |10.0.1.4|  |  |
  |  |   +-----+------+  +-----+------+  +-----+------+  +---+----+  |  |
  |  |         |               |               |              |       |  |
  |  +---------|---------------|---------------|--------------|-------+  |
  |            |               |               |              |          |
  +---------------------------------------------------------------------+
                             |
              +--------------+---------------+
              | Firewall: "firewall01"       |
              | No public SSH                |
              | All traffic within subnet    |
              +--------------+---------------+
                             |
                     +-------+--------+
                     |   Tailscale    |
                     +----------------+
```

Four `cx33` servers running Ubuntu 24.04 in Nuremberg. Nodes join Tailscale at boot via cloud-init and are administered over Tailscale SSH from then on; the firewall has no public SSH access, only internal subnet traffic.

## Prerequisites

- [uv](https://docs.astral.sh/uv/) -- Python package manager
- [OpenTofu](https://opentofu.org/docs/intro/install/) ~> 1.11
- [mise](https://mise.jdx.dev/) -- tool version management and environment variable loading
- A [GitHub](https://github.com/) account with a public SSH key added, and a personal access token for GHCR (GitHub Container Registry)
- A [Hetzner Cloud](https://www.hetzner.com/cloud/) account with an API token
- A [Tailscale](https://tailscale.com/) account with an auth key

## Getting Started

### 1. Clone the repository

```sh
git clone git@github.com:ubiquitousbyte/homelab.git
cd homelab
```

### 2. Set up environment variables

Copy the example file and fill in your values:

```sh
cp mise.local.toml.example mise.local.toml
```

Edit `mise.local.toml` and replace the placeholder values with your actual credentials, then let mise pick it up:

```sh
mise trust
```

`mise.local.toml` is gitignored -- it's the one place your secrets live, separate from the tracked `mise.toml` (tool versions and non-secret env config).

#### Secrets management

I use the [1Password CLI](https://developer.1password.com/docs/cli/) (`op`) to inject secrets into `mise.local.toml` rather than hardcoding them, via mise's `exec()` template function. For example:

```toml
[env]
HCLOUD_TOKEN = "{{exec(command=\"op read op://Vault/Item/credential\")}}"
```

This is optional -- you can set the values directly in `mise.local.toml` if you prefer a different approach.

### 3. Install dependencies

```sh
uv sync
```

### 4. Install Ansible collections

```sh
uv run ansible-galaxy install -r requirements.yml
```

### 5. Set up pre-commit hooks

```sh
uv run pre-commit install
```

## Usage

### Provision infrastructure

```sh
tofu init
tofu plan
tofu apply
```

### Configure servers

```sh
uv run ansible-playbook playbooks/site.yml
```

## Development

### Pre-commit hooks

This project uses [pre-commit](https://pre-commit.com/) to run checks locally before each commit:

- **Whitespace and formatting** -- trailing whitespace, end-of-file newlines, YAML syntax
- **Security** -- private key detection, large file prevention, IaC security scanning ([Checkov](https://www.checkov.io/))
- **Ansible** -- [ansible-lint](https://ansible.readthedocs.io/projects/lint/) with the `shared` profile
- **OpenTofu** -- `tofu fmt` formatting check
- **Shell** -- [ShellCheck](https://www.shellcheck.net/) for any shell scripts

To run all hooks manually:

```sh
uv run pre-commit run --all-files
```

### CI

GitHub Actions runs the same pre-commit hooks on every push to `main` and on pull requests, plus a separate OpenTofu validation step (`tofu init` + `tofu validate`).
