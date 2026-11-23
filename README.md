# nix-hgd1-cluster

NixOS configuration for my homelab at site `hgd1`: three small x86_64 nodes
(`hgd1-hv01`, `hgd1-hv02`, `hgd1-hv03`) running Ceph on their HDDs, with a
microVM platform ready for a future k3s cluster. The site network (OPNsense router and Aruba
switch) is configured, verified and documented here too.

I manage everything from this repo on my laptop and deploy over SSH.

## Current state — 2026-11-23

**Done:** network rollout N0–N7, Ceph (step 2), S3 HA/TLS (step 2.1),
and the step-3 VM platform.
All three hosts are on their static INFRA/storage addresses. The network passed 83/83 checks
and router/switch reboot tests. One base VM, `hgd1-k8m01`, is live; its data
and SSH identity survived VM restarts, and a host deploy did not restart it.

Ceph is **HEALTH_OK**: three monitors in quorum, three HDD OSDs up/in, and
three S3 gateways serving one shared object store. All pools use three replicas
across hosts with `min_size=2`. RBD and S3 reads/writes passed with each host's
Ceph services down in turn; hv02/hv03 also passed actual reboot recovery.
Runtime-key backups are encrypted and decrypt-verified. See [CEPH.md](CEPH.md).

**S3 application endpoint: [`https://s3.lan.buunk.org`](https://s3.lan.buunk.org)**
(private VIP `10.10.30.10`). HAProxy/Keepalived run on all three hosts, with
trusted Let's Encrypt certificates obtained through Cloudflare DNS-01.
Signed S3 operations, an interrupted upload retry, proxy failure and VIP-owner
reboot recovery passed. No public exposure or k3s dependency. See
[S3-HA.md](S3-HA.md), including laptop access through the existing storage block.

**Still pending:**

- **hv02 virtualization:** enable VT-x in BIOS, verify KVM, then enable guests
  there. Its HDD test has passed; use the Ceph one-host maintenance procedure.
- **k3s (step 4):** not installed. The other four VM definitions remain disabled.

Deployment, VM and storage runbooks are linked below. Ceph uses only the
reserved HDDs; host/VM disks remain on NVMe. This Ceph rollout did not change
the separate GPU server's VM setup.

## Documentation

- [PLAN.md](PLAN.md): the overall design and the steps to get there
- [ROLLOUT.md](ROLLOUT.md): the order of work for network, hosts, Ceph and
  remote access
- [DEVELOPMENT.md](DEVELOPMENT.md): how I edit, validate, deploy, verify and
  roll back
- [CEPH.md](CEPH.md): disk qualification, S3 endpoints and bucket access
- [S3-HA.md](S3-HA.md): stable HTTPS endpoint, certificates, failover and operations
- [VMS.md](VMS.md): live VM inventory, persistence, lifecycle and updates
- [network/](network/): the site network design, bootstrap and remote access

## Layout

| Path | What |
| --- | --- |
| `inventory.nix` | Cluster facts: IPs, MACs, disks, host keys, Ceph ids |
| `hosts/common.nix` | Settings shared by every node |
| `hosts/<host>/` | Per-node config and hardware configuration |
| `modules/network.nix` | VLAN networking |
| `modules/ceph.nix` | Ceph mon, mgr, osd and rgw |
| `modules/s3-ha.nix` | Storage VIP, HAProxy, Keepalived and automated trusted TLS |
| `modules/remote-access.nix` | Cloudflare tunnel for remote access |
| `modules/hypervisor.nix`, `modules/vm-guest.nix` | Declarative microVM host/guest platform |
| `scripts/vm.sh` | Inventory/key-checked VM lifecycle commands |
| `secrets/` | agenix recipients and encrypted secrets |
| `scripts/deploy.sh` | `scripts/deploy.sh <host> [switch\|boot\|test\|dry-activate]` |
| `scripts/ceph-bootstrap.sh` | One-time Ceph bootstrap |

SSH is key-only, root login is disabled and `jurre` has passwordless sudo.
The nodes now live at infra `10.10.20.11–13` and storage
`10.10.30.11–13` ([network/PLAN.md](network/PLAN.md)), so
`ssh jurre@10.10.20.11` gets me onto `hgd1-hv01`.

## Roadmap

Status as of 2026-11-23. Network steps `N*` are in
[network/PLAN.md](network/PLAN.md), cluster steps in [PLAN.md](PLAN.md).

| Step | What | Status |
| --- | --- | --- |
| N0 | Network bootstrap: cabling, OPNsense install, SSH access | **Done** 2026-11-21 |
| N1 | OPNsense base: firmware 26.7.9_3, `hgd1-fw01`, Unbound DNSSEC, NTP, backups | **Done** 2026-11-21 |
| N2 | OPNsense VLANs 20/40/100, DHCP on mgmt and users, outbound NAT | **Done** 2026-11-21 |
| N3 | Aruba `hgd1-sw01` at `10.10.10.2`, VLANs, port roles, key-based SSH | **Done** 2026-11-21 |
| N4 | Firewall policy between VLANs (bootstrap WAN access later closed in N7) | **Done** 2026-11-21 |
| – | `hgd1-gpu1` on INFRA `10.10.20.50`, gaming VM on USERS `10.10.100.50`, Sunshine reachable from the home network | **Done** 2026-11-21 |
| N5 / 1 | Move `hgd1-hv01..03` to their static VLAN 20/30/40 addresses | **Done** 2026-11-22; ports 5/7/9 native 20, tagged 30/40; each host rebooted and verified |
| N6 | Verify the network | **Done** 2026-11-22; 83/83 probes, router/switch reboots, saved VLANs, node isolation and unrouted storage verified |
| N7 | Cloudflare Zero Trust remote access, close bootstrap WAN management | **Done** 2026-11-23 |
| 2 | Ceph on the nodes (mon/mgr/osd/rgw) | **Done** 2026-11-23; HEALTH_OK, 3 mons/OSDs/RGWs, replica 3/min_size 2, RBD/S3 and one-host-outage recovery verified |
| 2.1 | S3 HA endpoint and trusted HTTPS | **Done** 2026-11-23; VIP failover, signed S3/multipart/presigned requests, upload retry and owner reboot verified |
| 3 | VM platform (microvm.nix) | **Done** 2026-11-22; one empty VM live, SSH/storage/internet and restart persistence verified; host deploy does not restart guests |
| 4 | k3s nodes (3 servers, 2 agents) | Planned |
| 5 | Operations docs | **Partial**: deployment, VM lifecycle and Ceph/S3 runbooks written; workload-aware procedures follow step 4 |
| 6 | Platform add-ons on k3s (workloads repo) | Planned |
| 7 | Monitoring and logs | Planned |
| 8 | Apps, Cloudreve first | Planned |
| 9 | My own backend for monitoring and small actions | Later |

Still to do outside the repo:

- Reserve WAN `192.168.2.12` on the home router for MAC `90:1b:0e:fa:70:dd`.
- Update the Aruba firmware (still `YA.16.02.0012`).

## VM platform

`hgd1-k8m01` is running on hv01 at `10.10.40.11` with storage `10.10.30.21`,
2 vCPUs, 4 GiB RAM and a persistent 60 GiB sparse NVMe volume. It is a base
NixOS VM, **not yet a k3s server**. The other four entries remain disabled until
step 4. See [VMS.md](VMS.md) for lifecycle, SSH and update commands.

hv02 currently exposes no VT-x/KVM: enable virtualization in its BIOS before
enabling guests there. Its HDD test has passed; maintain Ceph one host at a
time. hv01/hv03 expose KVM.

## Nodes

All three run NixOS 26.05 with UEFI systemd-boot, a 1 GiB EFI partition and
an ext4 root on the rest of the NVMe; `/srv/volumes` lives on that root. No
swap. Each HDD now holds its inventory-defined LVM/BlueStore OSD; NVMe layout
is unchanged. Each node has one NIC, `enp2s0`. They used to run Proxmox
as `pve0`–`pve2`.

| Node | Was | MAC | NVMe | Ceph HDD |
| --- | --- | --- | --- | --- |
| `hgd1-hv01` | pve0 | `fc:3f:db:10:c6:c9` | SK hynix `HFM256GD3GX013N` | HGST `JR1004BNK14S5M` |
| `hgd1-hv02` | pve1 | `fc:3f:db:0a:b1:c3` | Samsung `MZ9LQ256HBJQ` (replacement) | HGST `JR1000D30JXXWF` |
| `hgd1-hv03` | pve2 | `fc:3f:db:0a:c1:42` | SK hynix `HFM256GD3GX013N` (60% endurance used) | HGST `JR1000D30JXYRF` |

All three HDDs passed recent extended SMART tests before initialization, with
zero reallocated, pending and offline-uncorrectable sectors. Historical cautions
remain: hv01 has old unrecoverable-read errors (ATA counter saturated at 65535)
and hv03 reports `Runtime_Bad_Block = 1`. The current disks were accepted for
this homelab after the tests passed. Monitor them, replace failed media promptly,
and keep separate backups; replication does not erase disk history. See
[CEPH.md](CEPH.md).
Serials and disk ids are in `inventory.nix`.

When adopting this config on a fresh install, keep its `system.stateVersion`
and working bootloader settings, and don't import the installer's generated
`configuration.nix`.

## Finding the nodes

The live hosts are `hgd1-hv01.lan.buunk.org` (`10.10.20.11`),
`hgd1-hv02.lan.buunk.org` (`10.10.20.12`), and
`hgd1-hv03.lan.buunk.org` (`10.10.20.13`). With WARP connected (from anywhere, including home Wi-Fi):

```sh
warp-cli connect
ssh jurre@10.10.20.11
```

The WAN side has no management access any more; without WARP, use switch
port 1 (MGMT) or the OPNsense console.

Only a bootstrap/recovery generation uses DHCP on MGMT VLAN 10. Match its MAC
against `inventory.nix`; don't assume the old lease still belongs to that node.

They also announce `hgd1-hv0N.local` over mDNS, which only resolves from a
client on the same LAN.

Remote deployment does not create or synchronize `/etc/nixos` (it was absent
on these installations). All changes go through this repo and
[DEVELOPMENT.md](DEVELOPMENT.md).
