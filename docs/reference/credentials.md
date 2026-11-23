---
icon: lucide/lock-keyhole
---

# Credentials

Where every credential lives. This page never holds a value, only its
location. How to add or rotate them: [Manage secrets](../how-to/manage-secrets.md).

## Overview

| Where | What |
| --- | --- |
| **Git, encrypted** (`secrets/*.age`) | Secrets the hosts need to boot their services |
| **Hosts only** (root, mode 0600) | Runtime keys created on the hosts: Ceph, S3 users, certificates |
| **My laptop** | SSH keys, the kubeconfig, encrypted backups, router/switch exports |
| **Password manager** | Human logins and break-glass copies |

## Encrypted in Git

agenix files, encrypted to my laptop key and the three host keys
(`secrets/secrets.nix`).

| File | Holds | On the host |
| --- | --- | --- |
| `cloudflared-tunnel.age` | Tunnel credentials (JSON) | `/run/agenix/cloudflared-tunnel` |
| `s3-acme-cloudflare.age` | Cloudflare API token for DNS-01 | `/run/agenix/s3-acme-cloudflare` |
| `k3s-server-token.age` | k3s server join token | `/run/k3s-secrets/server/server-token` |
| `k3s-agent-token.age` | k3s agent join token | `/run/k3s-secrets/{server,agent}/agent-token` |
| `snmp-community.age` | snmp_exporter auth file with the switch's read-only community | `/run/agenix/snmp-community` |
| `api-tokens.age` | Hashes of the Platform API tokens (never the tokens) | `/run/agenix/api-tokens` |
| `clusterd-kubeconfig.age` | The API's Kubernetes ServiceAccount | `/run/agenix/clusterd-kubeconfig` |

## On the hosts only

| Credential | Location | Backup |
| --- | --- | --- |
| Ceph admin keyring | `/etc/ceph/ceph.client.admin.keyring` on every host | Encrypted, `~/.local/state/nix-hgd1-cluster/ceph-bootstrap/` |
| Ceph daemon keyrings | `/var/lib/ceph/` on every host | Same archive |
| Ceph key for the API (`client.clusterd`, read-only) | `/etc/ceph/ceph.client.clusterd.keyring` on every host | Same archive |
| S3 user `jurre` | `/root/jurre-s3-credentials.json` on hv01 | – |
| S3 users for apps | `/root/<app>-s3-credentials.json` on the host that created them | – |
| Let's Encrypt account and certificates | `/var/lib/acme/` on every host | Encrypted, `~/.local/state/nix-hgd1-cluster/s3-ha/` |
| SSH host keys | `/etc/ssh/ssh_host_ed25519_key`; public keys pinned in `inventory.nix` | – |
| VM SSH host keys | `/var/lib/ssh/` inside each VM; public keys in `inventory.nix` | – |
| k3s CA and certificates | `/var/lib/rancher/k3s/server/tls/` on the server VMs | etcd snapshots on the servers |

## On my laptop

| Credential | Location | Used for |
| --- | --- | --- |
| Admin SSH key | `~/.ssh/id_ed25519` | Logins on hosts, VMs and the router; decrypting every agenix secret |
| Switch SSH key | `~/.ssh/id_rsa_hgd1_network` | `manager` on `hgd1-sw01` |
| Kubeconfig | `~/.kube/hgd1.yaml` (mode 600) | Cluster admin; recreate with `scripts/kubeconfig.sh` |
| API token | `~/.config/labctl/token` (mode 600) | The `labctl` CLI |
| Router and switch exports | `~/.local/state/nix-cluster/network-rollout/` (mode 600) | Backups taken by `hgd1-network`; contain password hashes and keys |
| WARP enrolment | The WARP client | Device registration in team `buunk` |

The admin SSH key is the most important credential: it opens every machine
and every secret. Keep an offline backup of it.

## In other repos

| Credential | Where |
| --- | --- |
| Web UI `operator` token | Kubernetes Secret, encrypted with sops in `hgd1-k8s` |
| Secrets of cluster components (Cloudflare DNS token for cert-manager, …) | sops in `hgd1-k8s` |
| OPNsense API key, SNMP community, switch login for Ansible | sops (or ansible-vault) in `hgd1-network` |

## Password manager

| Credential | Why |
| --- | --- |
| Cloudflare account | Dashboard, Zero Trust, DNS |
| Tunnel credentials JSON | Break-glass copy of `cloudflared-tunnel.age` |
| OPNsense `root` password | Web UI and console (SSH uses the key) |
| Aruba `manager` password | Serial console (SSH uses the key) |

Hosts and VMs have **no** passwords: user `jurre` logs in with keys only and
has passwordless sudo.

## Future: a KMS

Tokens for the API and the web UI will be replaced by Keycloak (OIDC). Secrets for workloads
on k3s will move to a central secrets manager
(OpenBao or HashiCorp Vault) with logins through Keycloak (OIDC), and reach
the apps through the External Secrets Operator. agenix stays for everything
the hosts and the cluster need to boot, so the platform never depends on the
KMS to start.

## Related

- [Manage secrets](../how-to/manage-secrets.md) · [State outside Git](../operate/index.md#state-outside-git)
