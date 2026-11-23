---
icon: lucide/square-terminal
---

# CLI reference

Commands of `hgd1`, the client for the [Platform API](../concepts/api.md).
How to set it up: [Use the CLI](../how-to/use-the-cli.md).

<span class="status status--partial">In development</span>

## Install

| Where | How |
| --- | --- |
| This repo | `nix develop`, then `hgd1` |
| Anywhere with Nix | `nix run github:jurrebuunk/nix-hgd1-cluster#hgd1 -- <command>` |
| A NixOS machine | Add the flake's `packages.x86_64-linux.hgd1` to `environment.systemPackages` |

## Global options

| Option | Default | Meaning |
| --- | --- | --- |
| `--json` | off | Machine-readable output |
| `HGD1_API` (env) | `https://api.lan.buunk.org` | API base URL |
| `HGD1_TOKEN` (env) | `~/.config/hgd1/token` | Token, instead of the stored one |

## Commands

| Command | Scope | Does |
| --- | --- | --- |
| `hgd1 login` | – | Ask for a token, check it, store it in `~/.config/hgd1/token` |
| `hgd1 whoami` | read | Show the token's name and scope |
| `hgd1 token new --name N --scope read\|manage` | – | Generate a token and the hash line for `secrets/api-tokens.age` (runs locally) |
| `hgd1 status` | read | Hosts, VMs, k3s nodes, Ceph and VIP owners |
| `hgd1 metrics query <promql>` | read | Instant query |
| `hgd1 metrics range <promql> --since 1h --step 1m` | read | Range query |
| `hgd1 logs [--host H] [--unit U] [--since D] [--follow] [query]` | read | Search or follow logs (LogsQL) |
| `hgd1 vm restart <vm>` | manage | Drain, restart, wait for Ready, uncordon; asks for confirmation |

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
