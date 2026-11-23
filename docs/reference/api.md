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

<span class="status status--partial">v0.1.0, read-only</span> · Spec: [`api/openapi.yaml`](https://github.com/jurrebuunk/clusterd/blob/main/api/openapi.yaml)

## Conventions

| | |
| --- | --- |
| Base URL | `https://api.lan.buunk.org/v1` |
| Auth | Bearer token, scope `read`, `operator` or `manage` |
| Errors | HTTP status plus `{"error": "<message>"}` |
| Browsers | Never call the API directly; the [web UI](../concepts/web-ui.md) proxies with its own token |
| Request IDs | Every response has `X-Request-Id`; the same ID is in the access log |
| Audit | Every request is in the journal of `clusterd.service` (path, token name, status); actions get a full audit record in `v1.0` |

## System

| Method | Path | Scope | Returns |
| --- | --- | --- | --- |
| GET | `/v1/health` | none | `{"status":"ok"}` while this instance serves (Keepalived's check; doesn't depend on the stores) |
| GET | `/v1/whoami` | read | Token name and scope, the answering host and its version |
| GET | `/v1/node` | read | The answering host only: uptime, load, memory, VMs, VIPs held, local stores |
| GET | `/v1/status` | read | Hosts, VMs, k3s nodes, Ceph health, VIP owners. Built from every host's `/v1/node`, asked with your token |

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

Actions arrive with `v1.0`, one at a time; each wraps an existing safe
procedure. Until then `/v1/actions/…` answers 403 to `read` tokens and 404 to
the rest. The scope column says who may call it.

| Method | Path | Scope | Does |
| --- | --- | --- | --- |
| POST | `/v1/actions/vms/{name}/restart` | operator | `v1.0`: drain, restart `microvm@{name}`, wait for a new boot to be Ready, uncordon |

## Example

```sh
curl -s -G -H "Authorization: Bearer $(cat ~/.config/labctl/tokens/hgd1)" \
  "https://api.lan.buunk.org/v1/metrics/query" --data-urlencode 'query=probe_success == 0'
```

## Related

- [Platform API](../concepts/api.md) · [CLI reference](cli.md)
