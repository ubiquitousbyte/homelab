# homelab

Infrastructure-as-code for my homelab. Provisions servers on [Hetzner Cloud](https://www.hetzner.com/cloud/) with [OpenTofu](https://opentofu.org/) and configures a [HashiCorp Nomad](https://www.nomadproject.io/) cluster using [Ansible](https://docs.ansible.com/).

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
  |  |   |   Nomad    |  |   Nomad    |  |   Nomad    |  | Nomad  |  |  |
  |  |   |   Server   |  |   Client   |  |   Client   |  | Client |  |  |
  |  |   | 10.0.1.1   |  | 10.0.1.2   |  | 10.0.1.3   |  |10.0.1.4|  |  |
  |  |   +-----+------+  +-----+------+  +-----+------+  +---+----+  |  |
  |  |         |               |               |              |       |  |
  |  +---------|---------------|---------------|--------------|-------+  |
  |            |               |               |              |          |
  +---------------------------------------------------------------------+
                             |
              +--------------+---------------+
              | Firewall: "firewall01"       |
              | SSH + Nomad from home IP     |
              | All traffic within subnet    |
              +--------------+---------------+
                             |
                     +-------+--------+
                     |    Home IP     |
                     +----------------+
```

Four `cx33` servers running Ubuntu 24.04 in Nuremberg. One Nomad server node, three Nomad client nodes with Docker as the task driver. A firewall restricts external access to SSH (22) and Nomad (4646) from your home IP, while allowing all internal traffic within the subnet.

## Prerequisites

- [uv](https://docs.astral.sh/uv/) -- Python package manager
- [OpenTofu](https://opentofu.org/docs/intro/install/) ~> 1.11
- [direnv](https://direnv.net/) -- automatic environment variable loading
- An SSH keypair at `~/.ssh/id_ed25519`
- A [Hetzner Cloud](https://www.hetzner.com/cloud/) account with an API token
- A [GitHub](https://github.com/) account with a personal access token for GHCR (GitHub Container Registry)

## Getting Started

### 1. Clone the repository

```sh
git clone git@github.com:ubiquitousbyte/homelab.git
cd homelab
```

### 2. Set up environment variables

Copy the example files and fill in your values:

```sh
cp .envrc.example .envrc
cp .env.example .env
```

Edit `.envrc` and replace the placeholder values with your actual credentials. Edit `.env` and set your home IP address.

Then allow direnv to load the environment:

```sh
direnv allow
```

#### Secrets management

I use the [1Password CLI](https://developer.1password.com/docs/cli/) (`op`) to inject secrets into `.envrc` rather than hardcoding them. For example:

```sh
export HCLOUD_TOKEN=$(op read "op://Vault/Item/credential")
```

This is optional -- you can set the values directly in `.envrc` if you prefer a different approach.

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
