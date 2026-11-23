---
icon: lucide/list-tree
---

# Inventory fields

`inventory.nix` is a plain attribute set with every cluster fact and nothing
secret. Modules and scripts read it; `nix flake check` validates it.

## Top level

| Field | Meaning |
| --- | --- |
| `site.name`, `site.domain` | `hgd1`, `lan.buunk.org` |
| `vlans.<name>` | `id`, `subnet` and (except storage) `gateway` per VLAN |
| `prefixLength` | `24` for every subnet |
| `dns`, `ntp` | Servers for the hosts: OPNsense on infra |
| `ceph` | Cluster settings (below) |
| `hosts` | One entry per hypervisor (below) |
| `vms` | One entry per VM (below) |
| `k3s` | Cluster settings (below) |
| `monitoring` | Monitoring settings (below) |
| `remoteAccess` | `tunnelId` (null turns the module off) and `routes` |
| `adminKeys` | SSH public keys for login and agenix (my laptop) |

## hosts.&lt;name&gt;

| Field | Meaning |
| --- | --- |
| `ip.infra` | Management address on VLAN 20 |
| `ip.storage` | Address on `br-stor` (VLAN 30) |
| `interface` | The physical NIC (`enp2s0`) |
| `mac` | NIC MAC, for identification |
| `kvmAvailable` | VT-x is enabled; guests are refused when false |
| `hostKey` | Pinned SSH host key; checked by scripts, used by agenix |
| `hdd` | Whole-disk `/dev/disk/by-id/…` path handed to Ceph |
| `osd.id`, `osd.uuid` | The Ceph OSD on that disk |

## vms.&lt;name&gt;

| Field | Meaning |
| --- | --- |
| `host` | The hypervisor that runs it |
| `enabled` | Run it (true) or only reserve its identity (false) |
| `id` | 1–255, unique, never changed; derives MACs and TAP names |
| `role` | `server` or `agent` |
| `hostKey` | The VM's pinned SSH host key, from the host journal |
| `vcpu`, `memMB` | CPU and memory |
| `diskGB` | Size of `/var/lib` at creation; later changes don't resize |
| `ip.k8s`, `ip.storage` | Addresses on VLAN 40 and 30 |

## ceph

| Field | Meaning |
| --- | --- |
| `fsid` | Cluster ID |
| `s3.enable` | Turns the S3 endpoint modules on |
| `s3.hostname`, `s3.virtualIP` | `s3.lan.buunk.org`, `10.10.30.10` |
| `s3.virtualRouterId` | VRRP ID (30) |
| `s3.acmeEmail`, `s3.acmeServer` | Let's Encrypt account and directory |

## k3s

| Field | Meaning |
| --- | --- |
| `apiName`, `apiVIP` | `k8s.lan.buunk.org`, `10.10.40.10` |
| `virtualRouterId` | VRRP ID (40) |
| `bootstrapServer` | The server that runs `--cluster-init`; `null` once all servers joined |

## monitoring

| Field | Meaning |
| --- | --- |
| `hostname`, `virtualIP` | `mon.lan.buunk.org`, `10.10.20.10` |
| `virtualRouterId` | VRRP ID (20) |
| `retention.metrics`, `retention.logs` | `1y`, `90d` |
| `router`, `switch` | `name` and `ip`; scraped by every host, mapped to names in logs |
| `pingTargets` | Extra machines to ping, e.g. `hgd1-gpu1` |

## Checks

`modules/microvm/host/validation.nix` and `modules/s3-ha/default.nix` refuse,
among other things:

- duplicate VM ids or IPs, or IPs outside VLANs 40 and 30;
- a VM on a host that doesn't exist or has no KVM;
- more than 11 GiB of VM memory on one host;
- a k3s VIP that's in use or outside VLAN 40;
- a `bootstrapServer` that isn't a server VM;
- an S3 VIP that collides with a host or VM storage address;
- a monitoring VIP that's in use or outside the infra VLAN.
