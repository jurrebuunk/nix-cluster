# nix-cluster

Minimal NixOS 26.05 configs for `hgd1-hv01`, `hgd1-hv02`, and `hgd1-hv03` (x86_64).

See [PLAN.md](PLAN.md) for the cluster roadmap, [ROLLOUT.md](ROLLOUT.md) for
the static-network and Ceph rollout, and
[DEVELOPMENT.md](DEVELOPMENT.md) for the edit, validate, deploy, verify,
and rollback workflow. Manage changes from this repo on the laptop.

- Cluster facts (IPs, MACs, disks, Ceph ids): `inventory.nix`
- Shared config: `hosts/common.nix`; VLAN networking: `modules/network.nix`;
  Ceph mon/mgr/osd/rgw: `modules/ceph.nix`; Cloudflare remote access:
  `modules/remote-access.nix`; secrets (agenix): `secrets/`
- Per-host config: `hosts/<host>/default.nix`
- Static IPs on the site network ([network/PLAN.md](network/PLAN.md)):
  infra `10.10.20.11–13`, storage (Ceph) `10.10.30.11–13`, once
  [ROLLOUT.md](ROLLOUT.md) is done; until then DHCP (see below).
- Deploy: `scripts/deploy.sh <host> [switch|boot|test|dry-activate]`.
- SSH: `ssh jurre@10.10.20.11` (after rollout), using this laptop's
  `~/.ssh/id_ed25519`.
- Key-only SSH; root SSH disabled; `jurre` has passwordless sudo.

## Installation

The per-host notes below record the installation (DHCP era).

All three hosts are installed and verified. Each has its own generated hardware
configuration, UEFI systemd-boot, a 1 GiB EFI partition, and an ext4 root using
the remaining NVMe space. `/srv/volumes` shares that root filesystem.
Do not also import the installer's generated `configuration.nix`.

For an existing fresh install, preserve its `system.stateVersion` and working
bootloader settings when adopting this config.

## hgd1-hv01 (installed as pve0)

- DHCP on `enp2s0`, MAC `fc:3f:db:10:c6:c9`; hostname `pve0` at install time.
- Verified after reboot at `192.168.2.34`, resolved by the router as `pve0.home`.
  This is a DHCP lease, not a fixed address.
- Key-only SSH and passwordless sudo verified from the laptop; no failed units.
- NVMe `HFM256GD3GX013N-SKhynix`, serial `FYB3N06461330411F`:
  GPT, 1 GiB FAT32 `/boot`, remaining space ext4 `/`.
- `/srv/volumes` shares the root filesystem.
- HDD `HGST HTS721010A9E630`, serial `JR1004BNK14S5M`:
  previous Ceph/LVM and partition metadata removed; left blank for future Ceph.
- UEFI boot using systemd-boot; no swap.

## hgd1-hv02 (installed as pve1)

- DHCP on `enp2s0`, MAC `fc:3f:db:0a:b1:c3`; hostname `pve1` at install time.
- Verified after reboot at `192.168.2.35`, resolved by the router as `pve1.home`.
  This is a DHCP lease, not a fixed address.
- Key-only SSH and passwordless sudo verified from the laptop; no failed units.
- Replacement NVMe `SAMSUNG MZ9LQ256HBJQ-00000`, serial `S595NF1R307734`:
  GPT, 1 GiB FAT32 `/boot`, remaining space ext4 `/`.
- `/srv/volumes` shares the root filesystem.
- HDD `HGST HTS721010A9E630`, serial `JR1000D30JXXWF`:
  detected after installation/reboot; NTFS signatures and partition table removed,
  left blank for future Ceph. SMART passed, no reallocated or pending sectors.
- UEFI boot using systemd-boot; no swap.

## hgd1-hv03 (installed as pve2)

- DHCP on `enp2s0`, MAC `fc:3f:db:0a:c1:42`; hostname `pve2` at install time.
- Verified after reboot at `192.168.2.36`, resolved by the router as `pve2.home`.
  This is a DHCP lease, not a fixed address.
- Key-only SSH and passwordless sudo verified from the laptop; no failed units.
- NVMe `HFM256GD3GX013N-SKhynix`, serial `FYB4N002812204212`:
  GPT, 1 GiB FAT32 `/boot`, remaining space ext4 `/`.
  SMART passed, 60% endurance used, 100% spare, zero media errors.
- `/srv/volumes` shares the root filesystem.
- HDD `HGST HTS721010A9E630`, serial `JR1000D30JXYRF`:
  NTFS signatures and partition table removed after installation/reboot;
  left blank for future Ceph. SMART and a fresh short self-test passed,
  zero reallocated/pending/offline-uncorrectable sectors. Historical runtime
  bad-block counter is 1; run an extended self-test before Ceph deployment.
- UEFI boot using systemd-boot; no swap.

## Discovery and rebuilding

Discovery fallback: `nmap -sn -PS22 192.168.2.0/24`. Verified names and leases:

| Hostname | DHCP IP |
| --- | --- |
| pve0.home | 192.168.2.34 |
| pve1.home | 192.168.2.35 |
| pve2.home | 192.168.2.36 |

Hostname display depends on DNS. If nmap is not installed, use
`nix shell nixpkgs#nmap` first.

Avahi also advertises `hgd1-hv01.local`, `hgd1-hv02.local`, and `hgd1-hv03.local`; resolution
requires an mDNS-capable client on the same LAN. This laptop currently uses
the router's DNS (`<hostname>.home`), not an mDNS resolver.
No laptop networking configuration was changed.

`/etc/nixos` on each node is an installation-time snapshot, not an automatically
synchronized checkout. For ongoing development, use the laptop repo and the
remote deployment commands in [DEVELOPMENT.md](DEVELOPMENT.md).
