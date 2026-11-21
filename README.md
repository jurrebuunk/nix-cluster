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

## Roadmap

Where the site stands (updated 2026-11-22). Network steps `N*` are in
[network/PLAN.md](network/PLAN.md), cluster steps in [PLAN.md](PLAN.md), the
order of work in [ROLLOUT.md](ROLLOUT.md).

| Step | What | Status |
| --- | --- | --- |
| N0 | Network bootstrap: cabling, OPNsense install, SSH access | **Done** 2026-11-21 |
| N1 | OPNsense base: firmware 26.7.9_3, `hgd1-fw01`, Unbound DNSSEC, NTP, backups | **Done** 2026-11-21 |
| N2 | OPNsense VLANs 20/40/100, DHCP on mgmt and users, outbound NAT | **Done** 2026-11-21 |
| N3 | Aruba `hgd1-sw01` at `10.10.10.2`, VLANs, port roles, key-based SSH | **Done** 2026-11-21 |
| N4 | Firewall policy between VLANs (temporary WAN management rules still on) | **Done** 2026-11-21 |
| – | `nix-compute01` host to INFRA `10.10.20.50`, gaming VM to USERS `10.10.100.50`, Sunshine forwards from home WAN | **Done** 2026-11-21 |
| N5 / 1 | Move `hgd1-hv01..03` to static VLAN 20/30/40 addresses | **Next**: configured in Nix; hosts still offline (switch ports 5/7/9 wait on VLAN 10) |
| N6 | Verify network | **Partial**: 64 traffic checks via test clients and router/switch reboot tests passed; host-side checks wait for N5 |
| N7 | Cloudflare Zero Trust remote access, remove bootstrap WAN management | Planned, after N5 |
| 2 | Ceph on the hosts (mon/mgr/osd/rgw) | Configured, not deployed; run SMART long tests first |
| 3 | VM platform (microvm.nix) | Planned |
| 4 | k3s nodes (3 servers, 2 agents) | Planned |
| 5 | Operations docs | Planned |
| 6 | Platform add-ons on k3s (workloads repo) | Planned |
| 7 | Monitoring and logs | Planned |
| 8 | Apps, Cloudreve first | Planned |
| 9 | Own backend for monitoring and actions | Later |

Open items outside the repo: reserve WAN `192.168.2.12` on the home router for
MAC `90:1b:0e:fa:70:dd`; Aruba firmware is still `YA.16.02.0012` (needs a
verified vendor image); rotate passwords that were shared during bootstrap;
test actual Moonlight playback against the gaming VM. Router/switch backups,
test logs and the full handoff are in
`~/.local/state/nix-cluster/network-rollout/` on the laptop (not in Git: the
router XML contains secrets).

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

Since the site network went live (N0–N4), the hosts no longer sit on the home
network. Until N5 they get temporary `10.10.10.100–199` leases from OPNsense
on switch ports 5/7/9: match their MACs in OPNsense → Services → DHCPv4 →
Leases, or from the laptop:

```sh
ssh root@192.168.2.12 'arp -an -i igb0'
```

The table below records the original home-router leases (pre-OPNsense,
historical). Old discovery fallback: `nmap -sn -PS22 192.168.2.0/24`:

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
