---
icon: lucide/braces
---

# API reference

!!! repo "Lives in its own repo: clusterd"

    This page covers **the API endpoints** on the hgd1 cluster: how it fits in and how I
    use it here. Code, development, releases and the full documentation are in
    the repo.

    [:fontawesome-brands-github: jurrebuunk/clusterd](https://github.com/jurrebuunk/clusterd){ .md-button .md-button--primary }

Endpoints of the [Platform API](../concepts/api.md) at
`https://api.lan.buunk.org`. All responses are JSON. Every endpoint except
`/v1/health` needs `Authorization: Bearer <token>`.

<span class="status">v1.2.0</span> · Spec: [`api/openapi.yaml`](https://github.com/jurrebuunk/clusterd/blob/main/api/openapi.yaml)

## Conventions

| | |
| --- | --- |
| Base URL | `https://api.lan.buunk.org/v1` |
| Auth | Bearer token, scope `read`, `operator` or `manage` |
| Errors | HTTP status plus `{"error": "<message>"}` |
| Browsers | Never call the API directly; the [web UI](../concepts/web-ui.md) proxies with its own token |
| Request IDs | Every response has `X-Request-Id`; the same ID is in the access log |
| Collections | `{"items": […], "errors": […]}`; `errors` lists parts that couldn't be read, the rest is still there. `/{name}` is one item, or 404 |
| Audit | Every request is in the journal of `clusterd.service` (path, token name, status); actions and S3 writes also get `msg=audit` records, which `/v1/operations` reads |
| Stability | `/v1` only changes in backward-compatible ways from `2.0.0` on |

## System

| Method | Path | Scope | Returns |
| --- | --- | --- | --- |
| GET | `/v1/health` | none | `{"status":"ok"}` while this instance serves (Keepalived's check; doesn't depend on the stores) |
| GET | `/v1/whoami` | read | Token name and scope, the answering host and its version |
| GET | `/v1/status` | read | Everything in one answer: hosts, VMs, nodes, Ceph, VIPs, disks, S3 |
| GET | `/v1/checks` | read | `{"status", "checks": [{"name", "status", "message"}]}`: `ok`, `warn` or `fail` per area; `status` is the worst |
| GET | `/v1/internal/node` | read | The answering host's own facts; peers ask it for the lists below, with your token. Not for clients |

## Resources

| Method | Path | Scope | Returns |
| --- | --- | --- | --- |
| GET | `/v1/hosts`, `/v1/hosts/{name}` | read | Reachable, clusterd version, `nixos` (version, `revision`: the git commit it was built from, `generation`, `reboot_required`), uptime, load, memory, stores, `maintenance` |
| GET | `/v1/vms`, `/v1/vms/{name}` | read | Every VM in the inventory and its state |
| GET | `/v1/nodes`, `/v1/nodes/{name}` | read | Kubernetes nodes: Ready, schedulable, roles, version, zone |
| GET | `/v1/pods` | read | Every pod: node, phase, ready containers, restarts, `last_restart`, `reason`, `failing`. `?failing=true` keeps only those |
| GET | `/v1/ceph` | read | Health, checks, OSDs up/in, PGs, raw capacity; at most ~10 s old (`as_of`) |
| GET | `/v1/ceph/osds` | read | OSDs: host, device, size, used, up, in |
| GET | `/v1/disks` | read | Drives: size, used, role, wear, temperature, SMART |
| GET | `/v1/filesystems` | read | Filesystems of hosts and VMs |
| GET | `/v1/vips` | read | Which host holds each floating address |
| GET | `/v1/s3` | read | Endpoint, gateways, user and bucket counts, totals, data `pool` room, `cert_expires` |
| GET | `/v1/s3/buckets`, `/v1/s3/buckets/{name}` | read | Owner, objects, size, quota, created |
| GET | `/v1/s3/users`, `/v1/s3/users/{name}` | read | Name, display name, how many keys (never the keys), buckets, objects, size |
| GET | `/v1/operations` | read | Actions and S3 writes, newest first: `id`, `action`, `target`, `host`, `token`, `state` (`running`, `succeeded`, `failed`, `unknown`), `started`, `finished`, `error`. `?since=24h`, `?target=`, `?limit=100` |
| GET | `/v1/operations/{id}` | read | One, with its progress `events` |

Byte counts are bytes; percentages are 0–100. Operations come from the logs,
so they show up a few seconds after they happen.

## Metrics

A read-only proxy to VictoriaMetrics' Prometheus-compatible query API.

| Method | Path | Upstream |
| --- | --- | --- |
| GET | `/v1/metrics/query` | `/api/v1/query` |
| GET | `/v1/metrics/query_range` | `/api/v1/query_range` |
| GET | `/v1/metrics/series` | `/api/v1/series` |
| GET | `/v1/metrics/labels` | `/api/v1/labels` |
| GET | `/v1/metrics/label/{name}/values` | `/api/v1/label/{name}/values` |

Query parameters are passed through unchanged (`query`, `start`, `end`,
`step`, …). The store's status and body come back as they are; `502` means no
store answered. Scope: `read`.

## Logs

A read-only proxy to VictoriaLogs' LogsQL API.

| Method | Path | Upstream |
| --- | --- | --- |
| GET | `/v1/logs/query` | `/select/logsql/query` (JSON lines; streams when `?follow=1`) |
| GET | `/v1/logs/hits` | `/select/logsql/hits` |
| GET | `/v1/logs/streams` | `/select/logsql/streams` |

Scope: `read`. Without `limit`, a search returns at most 1000 lines; a follow
ends after one hour.

## Limits

| | |
| --- | --- |
| Query time | 30 s |
| Answer size | 64 MiB; larger answers are cut off |
| Follow | 1 h |
| Request body | 1 MiB |

## Actions

An action is a `POST` to its resource. Each wraps an existing safe procedure.

| Method | Path | Scope | Does |
| --- | --- | --- | --- |
| POST | `/v1/vms/{name}/restart` | operator | Cordon, drain, restart `microvm@{name}`, wait for a new boot to be Ready, uncordon, check the k3s API |
| POST | `/v1/vms/{name}/stop` | operator | Cordon, drain, stop `microvm@{name}`; the node stays cordoned |
| POST | `/v1/vms/{name}/start` | operator | Start it (`412` when it runs), wait Ready, uncordon |
| POST | `/v1/nodes/{name}/cordon` | operator | Mark the node unschedulable; answers the finished operation |
| POST | `/v1/nodes/{name}/uncordon` | operator | Mark it schedulable again |
| POST | `/v1/hosts/{name}/maintenance` | manage | Checks (no other host in maintenance, nodes elsewhere Ready, etcd quorum, `ceph osd ok-to-stop`), drain and stop its VMs, per-host `noout`. `reboot=true` reboots it after |
| POST | `/v1/hosts/{name}/resume` | manage | Start its VMs, wait Ready, uncordon, unset `noout`, wait for clean PGs |

VM actions run on the VM's host, host actions on that host; another
instance forwards the request with your token. Host plans list `vms` (in the
order they're handled) and `osds` instead of `evict`.

| Query | Answer |
| --- | --- |
| `dry_run=true` | `200` with the plan: `host`, `roles`, `evict` (pods), `skipped`, `steps`, and `lock_holder` when busy. Nothing changes |
| (none) | `202` with the operation (`state: running`) and `Location: /v1/operations/{id}`; the action runs on |
| `wait=true` | `200` with `application/x-ndjson`: one `{"time","status","message"}` per line, `status` is `progress` until a final `done` or `error`. `Location` names the operation |

| Status | Means | Changed anything? |
| --- | --- | --- |
| 404 | No such VM, node or host | No |
| 409 | Another action holds the lock (the message names it) | No |
| 412 | Not safe now: another node not Ready, etcd quorum, a pod without a controller, VM disabled | No |
| 502 | The VM's host didn't answer | No |
| `failed` operation, or last line `error` | Failed during the run; a failed drain uncordons again, a VM that didn't come back stays cordoned | Yes |

## S3 users and buckets

Writes need `manage`. The API's own RGW user (`clusterd`) is left out of
lists and can't be changed here.

| Method | Path | Body | Does |
| --- | --- | --- | --- |
| POST | `/v1/s3/users` | `{"name", "display_name"}` | Create a user with one key: `201` with `{"user", "access_key", "secret_key", "endpoint"}`, the only time the secret is shown |
| POST | `/v1/s3/users/{name}/keys` | – | A new key (same answer) and the old ones removed |
| DELETE | `/v1/s3/users/{name}` | – | `204`; `412` while it owns buckets |
| POST | `/v1/s3/buckets` | `{"name", "owner", "quota_bytes"}` | Create it with the owner's own key: `201` with the bucket |
| PATCH | `/v1/s3/buckets/{name}` | `{"quota_bytes"}` | Set the size limit; `0` removes it |
| DELETE | `/v1/s3/buckets/{name}` | – | `204`; `412` while it holds objects, unless `?force=true` |

## Example

```sh
curl -s -G -H "Authorization: Bearer $(cat ~/.config/labctl/tokens/hgd1)" \
  "https://api.lan.buunk.org/v1/metrics/query" --data-urlencode 'query=probe_success == 0'
```

## Related

- [Platform API](../concepts/api.md) · [CLI reference](cli.md)
