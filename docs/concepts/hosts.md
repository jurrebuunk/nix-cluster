---
icon: lucide/server
---

# Hosts

Three identical machines, `hgd1-hv01..03`, run the same NixOS 26.05
configuration with per-host facts from the inventory. They are hypervisors
and Ceph nodes at once.

!!! info "At a glance"

    **Status** <span class="status">Done</span> · **Configured in**
    `hosts/`, `modules/`, `inventory.nix` → `hosts` · **Deploy**
    [Deploy a change](../how-to/deploy.md)

## Overview

| Host | Was | Infra IP | Storage IP | NVMe | Ceph HDD |
| --- | --- | --- | --- | --- | --- |
| `hgd1-hv01` | pve0 | `10.10.20.11` | `10.10.30.11` | SK hynix `HFM256GD3GX013N` | HGST `JR1004BNK14S5M` |
| `hgd1-hv02` | pve1 | `10.10.20.12` | `10.10.30.12` | Samsung `MZ9LQ256HBJQ` | HGST `JR1000D30JXXWF` |
| `hgd1-hv03` | pve2 | `10.10.20.13` | `10.10.30.13` | SK hynix `HFM256GD3GX013N` | HGST `JR1000D30JXYRF` |

- Intel i5-6500T, 16 GiB RAM, one 1 GbE NIC (`enp2s0`).
- UEFI with systemd-boot (20 generations kept), a 1 GiB EFI partition and an
  ext4 root on the NVMe. No swap.
- The whole HDD belongs to Ceph as an LVM/BlueStore OSD.
- VT-x is enabled in the BIOS on all three (hv02 since 2026-11-23).

## How it works

The laptop evaluates the flake; each host builds its own system over SSH and
activates it. There is no `/etc/nixos` on the hosts and no manual
configuration: everything comes from the repo.

| Concern | Setting | Where |
| --- | --- | --- |
| Nix | Flakes, store optimisation, weekly GC of generations older than 30 days | `hosts/common.nix` |
| SSH | Key-only, no root login, only on `enp2s0`; `jurre` has passwordless sudo | `hosts/common.nix` |
| Time | chrony, preferring OPNsense | `hosts/common.nix` |
| Logs | journald capped at 1 GiB / 30 days | `hosts/common.nix` |
| Discovery | Avahi publishes `hgd1-hvNN.local` on the management NIC | `hosts/common.nix` |
| Network | VLAN 20 address, `br-stor`, `br-k8s` | `modules/network.nix` |
| Storage | Ceph mon, mgr, OSD, RGW | `modules/ceph.nix` |
| S3 endpoint | HAProxy, Keepalived, ACME | `modules/s3-ha/` |
| Remote access | `cloudflared` | `modules/remote-access.nix` |
| VMs | microVM runners, TAPs, token sharing | `modules/microvm/host/` |
| Monitoring | Exporters, vmagent, VictoriaMetrics, VictoriaLogs, Vector | `modules/monitoring/` |

Each host's SSH host key is pinned in `inventory.nix`. Scripts refuse a host
whose key doesn't match, and agenix encrypts secrets to these keys.

## Configuration

- Shared settings: `hosts/common.nix`.
- Per host: `hosts/<host>/default.nix` (hostname, bootloader) and the
  generated `hardware-configuration.nix`.
- Facts: `inventory.nix` → `hosts.<name>` (see [Inventory fields](../reference/inventory.md)).
- A new feature becomes a module in `modules/`; all modules are imported for
  every host and switch themselves on through the inventory.

## Operating

```sh
ssh jurre@10.10.20.11 'hostname; nixos-version; systemctl is-system-running; systemctl --failed --no-pager'
```

- Changes: [Deploy a change](../how-to/deploy.md), [Roll back](../how-to/roll-back.md).
- Reboots and hardware work: [Host maintenance](../operate/host-maintenance.md).
- Reinstalling: [Disaster recovery](../operate/disaster-recovery.md#reinstall-a-host).

## Disk health

All three HDDs passed an extended SMART test right before Ceph took them,
with zero reallocated, pending and offline-uncorrectable sectors. Their
history still matters:

- **hv01 HDD:** old unrecoverable-read errors; the ATA error counter is
  saturated at 65535. The last logged error was at power-on hour 6858, long
  before the test (hour 14214).
- **hv03 HDD:** reports `Runtime_Bad_Block = 1`.
- **NVMe wear** (`smartctl_device_percentage_used`): hv01 47%, hv02 7%,
  hv03 60%. hv01 and hv03 are the ones to replace first. `labctl status disk`
  shows the current values, with size and how full every drive is.

I've accepted these used disks for a homelab. Ceph keeps three copies, but
replication is not a backup. [Monitoring](monitoring.md) collects SMART for every disk; replace failed media quickly.

## Troubleshooting

- **Deploy broke a host:** [Roll back](../how-to/roll-back.md).
- **Host down:** [Troubleshooting → Host down](../operate/troubleshooting.md#host-down).

## Related

- [Architecture](index.md) · [Ceph](ceph.md) · [VMs](vms.md)
