---
icon: lucide/file-code
---

# Files

Every file in the repo and what it configures. Links open the file on GitHub.

## Flake and inventory

| File | Configures |
| --- | --- |
| [`flake.nix`](https://github.com/jurrebuunk/nix-hgd1-cluster/blob/main/flake.nix) | Inputs, a `nixosConfiguration` per host and VM, the dev shell |
| [`flake.lock`](https://github.com/jurrebuunk/nix-hgd1-cluster/blob/main/flake.lock) | Exact input revisions |
| [`inventory.nix`](https://github.com/jurrebuunk/nix-hgd1-cluster/blob/main/inventory.nix) | All cluster facts ([fields](inventory.md)) |

## Hosts

| File | Configures |
| --- | --- |
| [`hosts/common.nix`](https://github.com/jurrebuunk/nix-hgd1-cluster/blob/main/hosts/common.nix) | Nix, SSH, users, chrony, journald, Avahi |
| [`hosts/<host>/`](https://github.com/jurrebuunk/nix-hgd1-cluster/tree/main/hosts) | Hostname, bootloader, hardware |
| [`modules/network.nix`](https://github.com/jurrebuunk/nix-hgd1-cluster/blob/main/modules/network.nix) | VLAN 20 address, `br-stor`, `br-k8s` |
| [`modules/ceph.nix`](https://github.com/jurrebuunk/nix-hgd1-cluster/blob/main/modules/ceph.nix) | Ceph daemons and firewall |
| [`modules/s3-ha/`](https://github.com/jurrebuunk/nix-hgd1-cluster/tree/main/modules/s3-ha) | S3 endpoint: `tls.nix`, `proxy.nix`, `failover.nix`, `firewall.nix` |
| [`modules/remote-access.nix`](https://github.com/jurrebuunk/nix-hgd1-cluster/blob/main/modules/remote-access.nix) | `cloudflared` tunnel |
| [`modules/monitoring/`](https://github.com/jurrebuunk/nix-hgd1-cluster/tree/main/modules/monitoring) | Monitoring: `storage.nix`, `collection.nix`, `logs.nix`, `vip.nix`, `firewall.nix` |
| [`modules/rollout-safety.nix`](https://github.com/jurrebuunk/nix-hgd1-cluster/blob/main/modules/rollout-safety.nix) | Opt-in self-reverting guard for risky network changes |

## VMs

| File | Configures |
| --- | --- |
| [`modules/microvm/host/`](https://github.com/jurrebuunk/nix-hgd1-cluster/tree/main/modules/microvm/host) | Runners (`default.nix`), checks (`validation.nix`), TAPs and isolation (`networking.nix`), tokens (`k3s-secrets.nix`) |
| [`modules/microvm/guest/`](https://github.com/jurrebuunk/nix-hgd1-cluster/tree/main/modules/microvm/guest) | Resources and disks (`default.nix`), NICs (`networking.nix`), SSH (`access.nix`), monitoring (`monitoring.nix`) |
| [`modules/microvm/guest/k3s/`](https://github.com/jurrebuunk/nix-hgd1-cluster/tree/main/modules/microvm/guest/k3s) | k3s (`default.nix`), API VIP (`api-vip.nix`), ports (`firewall.nix`), Ceph facts (`ceph.nix`) |
| [`lib/vm-network.nix`](https://github.com/jurrebuunk/nix-hgd1-cluster/blob/main/lib/vm-network.nix) | MACs and TAP names from a VM id |
| [`lib/k3s.nix`](https://github.com/jurrebuunk/nix-hgd1-cluster/blob/main/lib/k3s.nix) | Join URL and token paths |
| [`lib/logs.nix`](https://github.com/jurrebuunk/nix-hgd1-cluster/blob/main/lib/logs.nix) | Vector field cleanup and buffered sinks |

## Secrets

| File | Holds | Decrypted to |
| --- | --- | --- |
| `secrets/secrets.nix` | Recipients: `adminKeys` and every host key | – |
| `secrets/cloudflared-tunnel.age` | Tunnel credentials | `/run/agenix/cloudflared-tunnel` |
| `secrets/s3-acme-cloudflare.age` | Cloudflare DNS token | `/run/agenix/s3-acme-cloudflare` |
| `secrets/k3s-server-token.age` | k3s server token | `/run/k3s-secrets/server/server-token` |
| `secrets/k3s-agent-token.age` | k3s agent token | `/run/k3s-secrets/{server,agent}/agent-token` |
| `secrets/snmp-community.age` | snmp_exporter auth file | `/run/agenix/snmp-community` |

Where everything else lives: [Credentials](credentials.md).

## Scripts and docs

| File | Purpose |
| --- | --- |
| `scripts/*.sh` | See [Scripts](scripts.md) |
| `docs/`, `zensical.toml` | This site |
| `includes/abbreviations.md` | Glossary tooltips on every page |
| `.github/workflows/docs.yml` | Builds and publishes this site |
