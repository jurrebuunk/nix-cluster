---
icon: lucide/braces
---

# API reference

Endpoints of the [Platform API](../concepts/api.md) at
`https://api.lan.buunk.org`. All responses are JSON. Every endpoint except
`/v1/health` needs `Authorization: Bearer <token>`.

<span class="status status--partial">In development</span>

## Conventions

| | |
| --- | --- |
| Base URL | `https://api.lan.buunk.org/v1` |
| Auth | Bearer token, scope `read` or `manage` |
| Errors | HTTP status plus `{"error": "<message>"}` |
| Browser calls | CORS only for `inventory.nix` → `api.webOrigin` |
| Audit | Every `manage` request is logged by `clusterd.service` |

## System

| Method | Path | Scope | Returns |
| --- | --- | --- | --- |
| GET | `/v1/health` | none | `ok` when this instance and its local stores answer (used by Keepalived) |
| GET | `/v1/whoami` | read | Token name and scope |
| GET | `/v1/status` | read | Hosts, VMs, k3s nodes, Ceph health, VIP owners |

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
`step`, …). Scope: `read`.

## Logs

A read-only proxy to VictoriaLogs' LogsQL API.

| Method | Path | Upstream |
| --- | --- | --- |
| GET | `/v1/logs/query` | `/select/logsql/query` (JSON lines; streams when `?follow=1`) |
| GET | `/v1/logs/hits` | `/select/logsql/hits` |
| GET | `/v1/logs/streams` | `/select/logsql/streams` |

Scope: `read`.

## Actions

Scope: `manage`. Actions are added one at a time; each wraps an existing safe
procedure and is listed here when it exists.

| Method | Path | Does |
| --- | --- | --- |
| POST | `/v1/actions/vms/{name}/restart` | Drain, restart `microvm@{name}`, wait for a new boot to be Ready, uncordon |

## Example

```sh
curl -s -H "Authorization: Bearer $(cat ~/.config/hgd1/token)" \
  "https://api.lan.buunk.org/v1/metrics/query" --data-urlencode 'query=probe_success == 0'
```

## Related

- [Platform API](../concepts/api.md) · [CLI reference](cli.md)
