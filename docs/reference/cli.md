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

<span class="status">v1.2.0</span>

## Install

| Where | How |
| --- | --- |
| This repo | `nix develop`, then `labctl` |
| Anywhere with Nix | `nix run github:jurrebuunk/clusterd#labctl -- <command>` |
| Without Nix | A `labctl` binary for Linux or macOS from [GitHub Releases](https://github.com/jurrebuunk/clusterd/releases); check it against `checksums.txt` |
| A NixOS machine (my laptop) | Add `clusterd` as a flake input and `inputs.clusterd.packages.x86_64-linux.labctl` to `environment.systemPackages` |

## How commands look

Like `gh` and `docker`: a noun, then a verb. A few site-wide commands stand
on their own.

```
labctl status | health | logs | metrics query|range
labctl operation list|show                        (alias: op)
labctl host  list | show H | maintenance H | resume H
labctl vm    list | show V | start|stop|restart V | roll [V…]
labctl node  list | show N | cordon|uncordon N
labctl pod   list [--failing]
labctl ceph  status
labctl osd | disk | fs | vip  list
labctl s3    status
labctl s3    bucket list | show B | create B --owner U | quota B SIZE | delete B
labctl s3    user   list | show U | create U --out F | rotate-keys U --out F | delete U
labctl auth  login | logout | status | token create
labctl site  list | use S
labctl version | completion bash|zsh|fish
```

Every command answers `--help`; a typo gets a suggestion (`labctl vm stpo`
→ *did you mean stop?*); Tab completes commands and the names of VMs,
hosts, nodes, buckets, users and sites.

## Global options

| Option | Default | Meaning |
| --- | --- | --- |
| `-o`, `--output table\|json\|name` | `table` | Tables, the API's JSON, or one name per line (for scripts: `labctl vm list -o name`) |
| `--site S` | current site | Which site's API to use (sites in `~/.config/labctl/config.toml`) |
| `LABCTL_API` (env) | `https://api.lan.buunk.org` | API base URL |
| `LABCTL_TOKEN` (env) | `~/.config/labctl/tokens/<site>` | The token itself, instead of the stored one |
| `LABCTL_SITE` (env) | current site | Same as `--site` |

Global options go anywhere on the line. Problems in a table's data go to
stderr as `warning:` lines, so stdout stays clean.

## The site

| Command | Scope | Does |
| --- | --- | --- |
| `labctl status` | read | Everything as tables: hosts, VMs, nodes, Ceph, VIPs, disks, filesystems, S3 |
| `labctl health` | read | One line per area (hosts, units, VMs, nodes, pods, Ceph, VIPs, disks, S3, tunnel, monitoring): `ok`, `warn` or `fail` with the reason. Exit code 5 unless all `ok` |
| `labctl logs [--host H] [--unit U] [--since 1h] [--limit 100] [-f] [query]` | read | Search (newest lines, printed oldest first) or follow logs. `--unit clusterd` also matches `clusterd.service`; `--unit 'ceph-osd*'` matches a prefix. `query` is LogsQL; with a `\|` pipe it is sent as is |
| `labctl metrics query <promql> [--time T]` | read | Instant query |
| `labctl metrics range <promql> [--since 1h] [--step S]` | read | Range query; the step defaults to `since/60`, at least 15 s |
| `labctl operation list [--since 24h] [--target T]` | read | What actions ran: who, what, on what, result, how long. From the audit records in the logs, so a few seconds behind |
| `labctl operation show ID [-w]` | read | One action with its progress lines; `--watch` follows it until it ends |

## Resources

| Command | Scope | Does |
| --- | --- | --- |
| `labctl host list` / `show H` | read | Status (`Up`, `Maintenance`, `RebootNeeded`, stores down), clusterd version, the git commit it runs, uptime, load, memory. Warns when hosts run different commits |
| `labctl host maintenance H [--reboot]` | manage | Check it's safe, drain and stop the host's VMs, set `noout` for its OSDs; `--reboot` reboots it after |
| `labctl host resume H` | manage | Start its VMs, wait Ready, uncordon, unset `noout`, wait for clean PGs |
| `labctl vm list` / `show V` | read | VMs from the inventory and their state |
| `labctl vm restart V` | operator | Cordon, drain, restart, wait for a new boot to be Ready, uncordon |
| `labctl vm stop V` | operator | Cordon, drain, stop; the node stays cordoned until `vm start` |
| `labctl vm start V` | operator | Start a stopped VM, wait Ready, uncordon |
| `labctl vm roll [V…]` | operator | Restart every enabled VM (or the given ones), agents first, one at a time; stops at the first failure |
| `labctl node list` / `show N` | read | Kubernetes nodes: Ready, cordoned, roles, version, zone |
| `labctl node cordon\|uncordon N` | operator | Mark a node (un)schedulable, e.g. after a restart that left it cordoned |
| `labctl pod list [--failing]` | read | Pods of every namespace; `--failing`: crash-looping, can't pull, stuck Pending or not ready, or restarted in the last hour |
| `labctl ceph status` | read | Health, every check, OSDs up/in, PGs clean, raw capacity |
| `labctl osd list` | read | OSDs: host, drive, size, how full, up/in |
| `labctl disk list` | read | Drives: role, size, how full, wear, temperature, SMART |
| `labctl fs list` | read | Filesystems of hosts and VMs, how full |
| `labctl vip list` | read | Floating addresses and which host holds each |
| `labctl s3 status` | read | Gateways, users, buckets, what's stored, room left, certificate |
| `labctl s3 bucket list` / `show B` | read | Buckets: owner, objects, size, quota |
| `labctl s3 bucket create B --owner U [--quota 10G]` | manage | Create a bucket for a user, optionally with a size limit |
| `labctl s3 bucket quota B SIZE\|none` | manage | Set or remove the size limit (`10G`, `500Mi`) |
| `labctl s3 bucket delete B [--force]` | manage | Refused while it holds objects; `--force` deletes them too and asks you to type the bucket's name |
| `labctl s3 user list` / `show U` | read | Users with their buckets and usage; never their keys |
| `labctl s3 user create U --out F` | manage | Create a user; its key goes to the new file `F` (mode 600, `AWS_*` variables), never to the terminal |
| `labctl s3 user rotate-keys U --out F` | manage | A new key to `F`; the old ones are removed, so whatever used them stops working |
| `labctl s3 user delete U` | manage | Refused while it owns buckets |

## Access and configuration

| Command | Scope | Does |
| --- | --- | --- |
| `labctl auth login [--api URL] [--token-file F]` | – | Ask for a token (or read it from `F`), check it, store it in `~/.config/labctl/tokens/<site>`. `--api` adds a new site |
| `labctl auth logout` | – | Forget the site's token |
| `labctl auth status` | read | Token name, scope, site and the answering host |
| `labctl auth token create --name N --scope read\|operator\|manage [--out F]` | – | Generate a token and the hash line for `secrets/api-tokens.age` (runs locally). With `--out` the token goes to `F` (mode 600) and is never printed |
| `labctl site list` / `use S` | – | Known sites, and switch the current one |
| `labctl version` | read | `Client Version` and `Server Version` |
| `labctl completion bash\|zsh\|fish` | – | Completion script (the Nix package installs them) |

## Actions

Every action shows its steps and asks first (`-y`/`--yes` skips that and is
required without a terminal); `--dry-run` only prints the steps. By default
it follows the progress until the end; Ctrl-C stops following, not the
action. `--no-wait` starts it and prints its operation, to follow later with
`labctl operation show <id> --watch`.

## Files

| Path | Holds |
| --- | --- |
| `~/.config/labctl/config.toml` | Sites (`api`, optional `token_file`) and the current one. Without it: site `hgd1` at `https://api.lan.buunk.org` |
| `~/.config/labctl/tokens/<site>` | The token, mode 600 |

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Success |
| 1 | The API returned an error |
| 2 | Usage error |
| 3 | API unreachable (check WARP) |
| 4 | Token missing, invalid or not allowed (scope) |
| 5 | `labctl health`: not every check is `ok` |

## Related

- [API reference](api.md) · [Use the CLI](../how-to/use-the-cli.md)
