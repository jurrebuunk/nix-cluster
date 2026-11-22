# nix-hgd1-cluster

NixOS configuration for my homelab at site `hgd1`: three small x86_64 nodes
(`hgd1-hv01`, `hgd1-hv02`, `hgd1-hv03`) that will run Ceph on their HDDs and a
k3s cluster in microVMs on top. The site network (OPNsense router and Aruba
switch) is planned and documented here too.

I manage everything from this repo on my laptop and deploy over SSH.

- [PLAN.md](PLAN.md): the overall design and the steps to get there
- [ROLLOUT.md](ROLLOUT.md): the order of work for network, hosts, Ceph and
  remote access
- [DEVELOPMENT.md](DEVELOPMENT.md): how I edit, validate, deploy, verify and
  roll back
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
| `secrets/` | agenix recipients and encrypted secrets |
| `scripts/deploy.sh` | `scripts/deploy.sh <host> [switch\|boot\|test\|dry-activate]` |
| `scripts/ceph-bootstrap.sh` | One-time Ceph bootstrap |

SSH is key-only, root login is disabled and `jurre` has passwordless sudo.
Once the rollout is done, the nodes live at infra `10.10.20.11–13` and storage
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
| N5 / 1 | Move `hgd1-hv01..03` to their static VLAN 20/30/40 addresses | **Next**: configured in Nix, nodes not connected yet (switch ports 5/7/9) |
| N6 | Verify the network | **Partial**: router, switch and VLAN tests pass; host checks follow N5 |
| N7 | Cloudflare Zero Trust remote access, close bootstrap WAN management | Planned |
| 2 | Ceph on the nodes (mon/mgr/osd/rgw) | Configured, not deployed; SMART long tests first |
| 3 | VM platform (microvm.nix) | Planned |
| 4 | k3s nodes (3 servers, 2 agents) | Planned |
| 5 | Operations docs | Planned |
| 6 | Platform add-ons on k3s (workloads repo) | Planned |
| 7 | Monitoring and logs | Planned |
| 8 | Apps, Cloudreve first | Planned |
| 9 | My own backend for monitoring and small actions | Later |

Still to do outside the repo:

- Reserve WAN `192.168.2.12` on the home router for MAC `90:1b:0e:fa:70:dd`.
- Update the Aruba firmware (still `YA.16.02.0012`).

## Nodes

All three run NixOS 26.05 with UEFI systemd-boot, a 1 GiB EFI partition and
an ext4 root on the rest of the NVMe; `/srv/volumes` lives on that root. No
swap. The HDDs are wiped and reserved for Ceph. Each node has one NIC,
`enp2s0`. They used to run Proxmox as `pve0`–`pve2`.

| Node | Was | MAC | NVMe | Ceph HDD |
| --- | --- | --- | --- | --- |
| `hgd1-hv01` | pve0 | `fc:3f:db:10:c6:c9` | SK hynix `HFM256GD3GX013N` | HGST `JR1004BNK14S5M` |
| `hgd1-hv02` | pve1 | `fc:3f:db:0a:b1:c3` | Samsung `MZ9LQ256HBJQ` (replacement) | HGST `JR1000D30JXXWF` |
| `hgd1-hv03` | pve2 | `fc:3f:db:0a:c1:42` | SK hynix `HFM256GD3GX013N` (60% endurance used) | HGST `JR1000D30JXYRF` |

The HDD in `hgd1-hv03` has a historical bad-block count of 1, so it gets an
extended SMART test before it goes into Ceph. Serials and disk ids are in
`inventory.nix`.

When adopting this config on a fresh install, keep its `system.stateVersion`
and working bootloader settings, and don't import the installer's generated
`configuration.nix`.

## Finding the nodes

Until N5 the nodes get temporary `10.10.10.100–199` leases from OPNsense. I
find them by MAC under Services → DHCPv4 → Leases, or with:

```sh
ssh root@192.168.2.12 'arp -an -i igb0'
```

They also announce `hgd1-hv0N.local` over mDNS, which only resolves from a
client on the same LAN.

`/etc/nixos` on each node is just the installation snapshot. All changes go
through this repo and [DEVELOPMENT.md](DEVELOPMENT.md).
