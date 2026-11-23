# Hosts

The three hypervisors `hgd1-hv01`, `hgd1-hv02` and `hgd1-hv03` run the same
NixOS 26.05 configuration. Everything about them comes from this repo; there is
no `/etc/nixos` on them, and nothing should be changed by hand.

## The machines

| Host | Was | Infra IP | Storage IP | NVMe | Ceph HDD (serial) |
| --- | --- | --- | --- | --- | --- |
| `hgd1-hv01` | pve0 | `10.10.20.11` | `10.10.30.11` | SK hynix `HFM256GD3GX013N` | HGST `JR1004BNK14S5M` |
| `hgd1-hv02` | pve1 | `10.10.20.12` | `10.10.30.12` | Samsung `MZ9LQ256HBJQ` (replacement) | HGST `JR1000D30JXXWF` |
| `hgd1-hv03` | pve2 | `10.10.20.13` | `10.10.30.13` | SK hynix `HFM256GD3GX013N` (60% endurance used) | HGST `JR1000D30JXYRF` |

- UEFI with systemd-boot (20 generations kept), a 1 GiB EFI partition and an
  ext4 root on the rest of the NVMe. No swap.
- The whole HDD belongs to Ceph as an LVM/BlueStore OSD.
- hv01 and hv03 expose VT-x (`/dev/kvm`). **hv02 doesn't yet**: its BIOS has
  virtualization switched off, so `kvmAvailable = false` and it runs no VMs.

## Logging in

```sh
warp-cli connect                 # unless you're on the site network
ssh jurre@10.10.20.11            # or hgd1-hv01.lan.buunk.org
```

SSH is key-only, root login is disabled and `jurre` has passwordless sudo. SSH
only listens on the management NIC `enp2s0`, never on the storage or k8s
bridges. Each host's SSH host key is pinned in `inventory.nix`; the scripts
refuse to talk to a host whose key doesn't match.

## What every host runs

| Concern | Setting | Where |
| --- | --- | --- |
| Nix | Flakes on, store optimisation, weekly GC of generations older than 30 days | `hosts/common.nix` |
| Time | chrony, preferring OPNsense | `hosts/common.nix` |
| Logs | journald capped at 1 GiB / 30 days | `hosts/common.nix` |
| Discovery | Avahi publishes `hgd1-hvNN.local`, on the management NIC only | `hosts/common.nix`, `modules/network.nix` |
| Network | VLAN 20 address, `br-stor`, `br-k8s`, peers in `/etc/hosts` | `modules/network.nix` |
| Storage | Ceph mon, mgr, OSD, RGW | `modules/ceph.nix` |
| S3 endpoint | HAProxy, Keepalived, ACME | `modules/s3-ha/` |
| Remote access | `cloudflared` tunnel connector | `modules/remote-access.nix` |
| VMs | microVM runners, TAPs, k3s token sharing | `modules/microvm/host/` |

## Health at a glance

```sh
ssh jurre@10.10.20.11 'hostname; nixos-version; systemctl is-system-running; systemctl --failed --no-pager'
ssh jurre@10.10.20.11 'sudo ceph -s'
```

`systemctl is-system-running` should say `running`. More checks are in
[Operations](../operations/index.md).

## Disk health

All three HDDs passed an extended SMART test right before Ceph took them, with
zero reallocated, pending and offline-uncorrectable sectors. Their history
still matters:

- **hv01**: old unrecoverable-read errors; the ATA error counter is saturated
  at 65535. The last logged error was at power-on hour 6858, long before the
  test (hour 14214).
- **hv03**: reports `Runtime_Bad_Block = 1`.
- **hv03's NVMe** has used 60% of its rated endurance.

I accepted these disks for a homelab. Ceph keeps three copies, so one failed
disk costs no data, but replication is not a backup. Watch SMART and Ceph
health and replace failed media quickly. See
[Ceph](../storage/ceph.md#disk-health-and-risk).

## Reinstalling a host

When a node needs a fresh NixOS install:

1. Install NixOS with UEFI and systemd-boot on the NVMe. Leave the HDD alone.
2. Copy the new `hardware-configuration.nix` into `hosts/<host>/`. Keep the
   existing `system.stateVersion` and bootloader settings, and don't import the
   installer's `configuration.nix`.
3. The SSH host key changed: put the new public key in `inventory.nix`, then
   re-encrypt all secrets to it (`cd secrets && agenix -r`). See
   [Secrets](../operations/secrets.md).
4. Deploy with `scripts/deploy.sh`.
5. Ceph's monitor store and keyrings live on the NVMe root, so they are gone.
   Treat it as replacing a Ceph host: set `noout`, remove and re-add its
   monitor, and bring back its OSD with the keyring from the encrypted runtime
   backup, or recreate the OSD and let Ceph backfill. I haven't rehearsed this
   yet; plan it before you start (see [Recovery](../operations/recovery.md)).
