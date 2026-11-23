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

<span class="status">v1.0.0</span>

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
| `LABCTL_TOKEN` (env) | `~/.config/labctl/tokens/<site>` | The token itself, instead of the stored one |
| `LABCTL_SITE` (env) | current context | Same as `--site` |

## Commands

| Command | Scope | Does |
| --- | --- | --- |
| `labctl login [--api URL] [--token-file F]` | – | Ask for a token (or read it from `F`), check it, store it in `~/.config/labctl/tokens/<site>`. `--api` adds a new site |
| `labctl use [site]` | – | Switch the current context, or list them |
| `labctl whoami` | read | Token name, scope, site and the answering host |
| `labctl token new --name N --scope read\|operator\|manage [--out F]` | – | Generate a token and the hash line for `secrets/api-tokens.age` (runs locally). With `--out` the token goes to `F` (mode 600) and is never printed |
| `labctl status [host\|vm\|node\|ceph\|vip\|disk\|s3]` | read | Everything as tables, or one part (singular or plural; `k3s` = `node`) from its own endpoint. Problems go to stderr as `warning:` lines |
| `labctl metrics query <promql> [--time T]` | read | Instant query |
| `labctl metrics range <promql> [--since 1h] [--step S]` | read | Range query; the step defaults to `since/60`, at least 15 s |
| `labctl logs [--host H] [--unit U] [--since 1h] [--limit 100] [-f\|--follow] [query]` | read | Search (newest lines, printed oldest first) or follow logs. `--unit clusterd` also matches `clusterd.service`. `query` is LogsQL; with a `\|` pipe it is sent as is |
| `labctl version` | read | `Client Version` and `Server Version` |
| `labctl completion bash\|zsh\|fish` | – | Completion script (the Nix package installs them) |
| `labctl vm restart <vm> [-y\|--yes] [--dry-run]` | operator | Cordon, drain, restart, wait for a new boot to be Ready, uncordon. Asks first (needs `--yes` without a terminal); `--dry-run` only prints the steps; Ctrl-C stops following, not the restart |

New actions get a command here when the API gets the endpoint.

## Files

| Path | Holds |
| --- | --- |
| `~/.config/labctl/config.toml` | Sites (`api`, optional `token_file`) and the current one. Without it: site `hgd1` at `https://api.lan.buunk.org` |
| `~/.config/labctl/tokens/<site>` | The token, mode 600 |

`--site`, `LABCTL_SITE` and `--json` work before or after the command.

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
