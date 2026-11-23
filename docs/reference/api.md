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

<span class="status">v1.0.0</span> · Spec: [`api/openapi.yaml`](https://github.com/jurrebuunk/clusterd/blob/main/api/openapi.yaml)

## Conventions

| | |
| --- | --- |
| Base URL | `https://api.lan.buunk.org/v1` |
| Auth | Bearer token, scope `read`, `operator` or `manage` |
| Errors | HTTP status plus `{"error": "<message>"}` |
| Browsers | Never call the API directly; the [web UI](../concepts/web-ui.md) proxies with its own token |
| Request IDs | Every response has `X-Request-Id`; the same ID is in the access log |
| Audit | Every request is in the journal of `clusterd.service` (path, token name, status); actions also get `msg=audit` start and end records |
| Stability | `/v1` only changes in backward-compatible ways from `1.0.0` on |

## System

| Method | Path | Scope | Returns |
| --- | --- | --- | --- |
| GET | `/v1/health` | none | `{"status":"ok"}` while this instance serves (Keepalived's check; doesn't depend on the stores) |
| GET | `/v1/whoami` | read | Token name and scope, the answering host and its version |
| GET | `/v1/node` | read | The answering host only: uptime, load, memory, VMs, VIPs held, local stores |
| GET | `/v1/status` | read | Everything below in one answer. Host facts come from every host's `/v1/node`, asked with your token |
| GET | `/v1/status/hosts` | read | `{"hosts": […]}`: reachable, version, uptime, load, memory, stores |
| GET | `/v1/status/vms` | read | `{"vms": […]}`: every VM in the inventory and its state |
| GET | `/v1/status/k3s` | read | Kubernetes nodes: Ready, schedulable, roles, version, zone |
| GET | `/v1/status/ceph` | read | Health, checks, OSDs up/in, PGs, raw capacity; at most ~10 s old (`as_of`) |
| GET | `/v1/status/vips` | read | `{"vips": […]}`: which host holds each floating address |
| GET | `/v1/status/disks` | read | `disks` (size, used, role, wear, temperature, SMART), `filesystems` (hosts and VMs), `osds` |
| GET | `/v1/status/s3` | read | Endpoint, gateways, users, `buckets` (objects, size, quota), totals, data `pool` room, `cert_expires` |

A part that can't be read is reported inside the answer (`error` or
`errors`), never as a failed request. Byte counts are bytes; percentages are
0–100.

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
| Request body | 1 MiB (all endpoints are GET) |

## Actions

Each action wraps an existing safe procedure. Other paths under
`/v1/actions/` answer 403 to `read` tokens and 404 to the rest.

| Method | Path | Scope | Does |
| --- | --- | --- | --- |
| POST | `/v1/actions/vms/{name}/restart` | operator | Cordon, drain, restart `microvm@{name}`, wait for a new boot to be Ready, uncordon, check the k3s API |

| Query | Effect |
| --- | --- |
| `dry_run=1` | Nothing changes; returns the plan: `host`, `roles`, `evict` (pods), `skipped`, `steps`, and `lock_holder` when busy |
| (none) | Runs it; `200` with `application/x-ndjson`: one `{"time","status","message"}` per line, `status` is `progress` until a final `done` or `error` |

| Status | Means | Changed anything? |
| --- | --- | --- |
| 404 | No such VM in the inventory | No |
| 409 | Another action holds the lock (the message names it) | No |
| 412 | Not safe now: another node not Ready, etcd quorum, a pod without a controller, VM disabled | No |
| 502 | The VM's host didn't answer | No |
| 200, last line `error` | Failed during the run; a failed drain uncordons again, a VM that didn't come back stays cordoned | Yes |

## Example

```sh
curl -s -G -H "Authorization: Bearer $(cat ~/.config/labctl/tokens/hgd1)" \
  "https://api.lan.buunk.org/v1/metrics/query" --data-urlencode 'query=probe_success == 0'
```

## Related

- [Platform API](../concepts/api.md) · [CLI reference](cli.md)
