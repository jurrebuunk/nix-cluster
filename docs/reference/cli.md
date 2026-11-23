---
icon: lucide/square-terminal
---

# CLI reference

!!! repo "Lives in its own repo: clusterd"

    This page covers **the `labctl` commands** on the hgd1 cluster: how it fits in and how I
    use it here. Code, development, releases and the full documentation are in
    the repo.

    [:fontawesome-brands-github: jurrebuunk/clusterd](https://github.com/jurrebuunk/clusterd){ .md-button .md-button--primary }

Commands of `labctl`, the client for the [Platform API](../concepts/api.md).
How to set it up: [Use the CLI](../how-to/use-the-cli.md).

<span class="status status--partial">In development</span>

## Install

| Where | How |
| --- | --- |
| This repo | `nix develop`, then `labctl` |
| Anywhere with Nix | `nix run github:jurrebuunk/clusterd#labctl -- <command>` |
| Without Nix | A `labctl` binary for Linux or macOS from [GitHub Releases](https://github.com/jurrebuunk/clusterd/releases); check it against `checksums.txt` |
| A NixOS machine (my laptop) | Add `clusterd` as a flake input and `inputs.clusterd.packages.x86_64-linux.labctl` to `environment.systemPackages` |

## Global options

| Option | Default | Meaning |
| --- | --- | --- |
| `--json` | off | Machine-readable output |
| `--site S` | current context | Which site's API to use (contexts in `~/.config/labctl/config.toml`) |
| `LABCTL_API` (env) | `https://api.lan.buunk.org` | API base URL |
| `LABCTL_TOKEN` (env) | `~/.config/labctl/token` | Token, instead of the stored one |
| `LABCTL_SITE` (env) | current context | Same as `--site` |

## Commands

| Command | Scope | Does |
| --- | --- | --- |
| `labctl login` | – | Ask for a token, check it, store it in `~/.config/labctl/token` |
| `labctl use <site>` | – | Switch the current context |
| `labctl whoami` | read | Show the site, token name and scope |
| `labctl token new --name N --scope read\|operator\|manage` | – | Generate a token and the hash line for `secrets/api-tokens.age` (runs locally) |
| `labctl status` | read | Hosts, VMs, k3s nodes, Ceph and VIP owners |
| `labctl metrics query <promql>` | read | Instant query |
| `labctl metrics range <promql> --since 1h --step 1m` | read | Range query |
| `labctl logs [--host H] [--unit U] [--since D] [--follow] [query]` | read | Search or follow logs (LogsQL) |
| `labctl vm restart <vm>` | operator | Drain, restart, wait for Ready, uncordon; asks for confirmation |

New actions get a command here when the API gets the endpoint.

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Success |
| 1 | The API returned an error |
| 2 | Usage error |
| 3 | API unreachable (check WARP) |
| 4 | Token missing, invalid or not allowed (scope) |

## Related

- [API reference](api.md) · [Use the CLI](../how-to/use-the-cli.md)
