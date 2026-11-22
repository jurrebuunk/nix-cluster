# nix-hgd1-cluster

NixOS configuration for my homelab at site `hgd1`: three small x86_64 nodes
(`hgd1-hv01`, `hgd1-hv02`, `hgd1-hv03`) that will run Ceph on their HDDs and a
k3s cluster in microVMs on top. The site network (OPNsense router and Aruba
switch) is configured, verified and documented here too.

I manage everything from this repo on my laptop and deploy over SSH.

## Current state — 2026-11-22

**Done:** network rollout N0–N6 and the step-3 VM platform. All three hosts
are on their static INFRA/storage addresses. The network passed 83/83 checks
and router/switch reboot tests. One base VM, `hgd1-k8m01`, is live; its data
and SSH identity survived VM restarts, and a host deploy did not restart it.

**Still pending:**

- **Ceph:** HDD extended SMART tests are still running. No OSDs, pools, S3
  endpoints or buckets have been initialized. Zero current bad-sector counters
  do not mean the disks are qualified; hv01's HDD has concerning historical
  read errors and hv03 has a historical bad-block indicator.
- **hv02 virtualization:** enable VT-x in BIOS only after its disk test finishes,
  then verify KVM before enabling guests there. Do not reboot hosts during tests.
- **k3s (step 4):** not installed. The other four VM definitions remain disabled.
- **N7:** in progress. Tunnel `hgd1-admin`, routes, WARP settings and the OPNsense rule are in place; next is deploying hv01–03 and testing from outside. Bootstrap WAN management stays until then.

Deployment, VM and storage runbooks are linked below. Network/VM work has not
initialized the reserved HDDs or changed the separate GPU server's VM setup.

## Documentation

- [PLAN.md](PLAN.md): the overall design and the steps to get there
- [ROLLOUT.md](ROLLOUT.md): the order of work for network, hosts, Ceph and
  remote access
- [DEVELOPMENT.md](DEVELOPMENT.md): how I edit, validate, deploy, verify and
  roll back
- [CEPH.md](CEPH.md): disk qualification, S3 endpoints and bucket access
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

Status as of 2026-11-22. Network steps `N*` are in
[network/PLAN.md](network/PLAN.md), cluster steps in [PLAN.md](PLAN.md).

| Step | What | Status |
| --- | --- | --- |
| N0 | Network bootstrap: cabling, OPNsense install, SSH access | **Done** 2026-11-21 |
| N1 | OPNsense base: firmware 26.7.9_3, `hgd1-fw01`, Unbound DNSSEC, NTP, backups | **Done** 2026-11-21 |
| N2 | OPNsense VLANs 20/40/100, DHCP on mgmt and users, outbound NAT | **Done** 2026-11-21 |
| N3 | Aruba `hgd1-sw01` at `10.10.10.2`, VLANs, port roles, key-based SSH | **Done** 2026-11-21 |
| N4 | Firewall policy between VLANs (temporary WAN management rules still on) | **Done** 2026-11-21 |
| – | `hgd1-gpu1` on INFRA `10.10.20.50`, gaming VM on USERS `10.10.100.50`, Sunshine reachable from the home network | **Done** 2026-11-21 |
| N5 / 1 | Move `hgd1-hv01..03` to their static VLAN 20/30/40 addresses | **Done** 2026-11-22; ports 5/7/9 native 20, tagged 30/40; each host rebooted and verified |
| N6 | Verify the network | **Done** 2026-11-22; 83/83 probes, router/switch reboots, saved VLANs, node isolation and unrouted storage verified |
| N7 | Cloudflare Zero Trust remote access, close bootstrap WAN management | **In progress (2026-11-23): Cloudflare side, tunnel secret and OPNsense rule done; deploy to hv01–03 and test pending**; temporary management rules remain |
| 2 | Ceph on the nodes (mon/mgr/osd/rgw) | Configuration deployed, services gated off; extended SMART tests pending, no disks initialized |
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

hv02 currently exposes no VT-x/KVM: enable virtualization in its BIOS after
its HDD test completes before enabling guests there. hv01/hv03 expose KVM.

## Nodes

All three run NixOS 26.05 with UEFI systemd-boot, a 1 GiB EFI partition and
an ext4 root on the rest of the NVMe; `/srv/volumes` lives on that root. No
swap. The HDDs had no filesystem signatures at preflight and have not been
initialized for Ceph. Each node has one NIC, `enp2s0`. They used to run Proxmox
as `pve0`–`pve2`.

| Node | Was | MAC | NVMe | Ceph HDD |
| --- | --- | --- | --- | --- |
| `hgd1-hv01` | pve0 | `fc:3f:db:10:c6:c9` | SK hynix `HFM256GD3GX013N` | HGST `JR1004BNK14S5M` |
| `hgd1-hv02` | pve1 | `fc:3f:db:0a:b1:c3` | Samsung `MZ9LQ256HBJQ` (replacement) | HGST `JR1000D30JXXWF` |
| `hgd1-hv03` | pve2 | `fc:3f:db:0a:c1:42` | SK hynix `HFM256GD3GX013N` (60% endurance used) | HGST `JR1000D30JXYRF` |

HDD qualification is pending: `hgd1-hv01` has historical unrecoverable-read
errors (ATA log counter saturated at 65535), and `hgd1-hv03` reports a historical
`Runtime_Bad_Block` count of 1. All three currently have zero reallocated,
pending and offline-uncorrectable sectors; that alone is not proof of healthy
media. Extended tests must pass before Ceph initialization. See [CEPH.md](CEPH.md).
Serials and disk ids are in `inventory.nix`.

When adopting this config on a fresh install, keep its `system.stateVersion`
and working bootloader settings, and don't import the installer's generated
`configuration.nix`.

## Finding the nodes

The live hosts are `hgd1-hv01.lan.buunk.org` (`10.10.20.11`),
`hgd1-hv02.lan.buunk.org` (`10.10.20.12`), and
`hgd1-hv03.lan.buunk.org` (`10.10.20.13`). From home Wi-Fi before N7:

```sh
ssh -J root@192.168.2.12 jurre@10.10.20.11
```

Only a bootstrap/recovery generation uses DHCP on MGMT VLAN 10. Match its MAC
against `inventory.nix`; don't assume the old lease still belongs to that node.

They also announce `hgd1-hv0N.local` over mDNS, which only resolves from a
client on the same LAN.

Remote deployment does not create or synchronize `/etc/nixos` (it was absent
on these installations). All changes go through this repo and
[DEVELOPMENT.md](DEVELOPMENT.md).
