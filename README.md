# nix-cluster

Minimal NixOS 26.05 configs for `pve0`, `pve1`, and `pve2` (x86_64).

- Shared config: `hosts/common.nix`
- Per-host config: `hosts/<host>/default.nix`
- DHCP networking; mDNS discovery as `<hostname>.local` on the local LAN.
- SSH: `ssh jurre@pve0.home` on the current LAN (or its DHCP IP), using this
  laptop's `~/.ssh/id_ed25519`.
- Key-only SSH; root SSH disabled; `jurre` has passwordless sudo.

## Before installing each host

`pve0` is installed and verified. `pve1` and `pve2` still have placeholder
hardware files and are **not bootable yet**.
We will choose disks and a bootloader separately for each remaining host. Replace that
host's `hardware-configuration.nix` with the generated hardware configuration
and add its bootloader settings before installation. Do not import the
installer's generated `configuration.nix` as well.

For an existing fresh install, preserve its `system.stateVersion` and working
bootloader settings when adopting this config.

Stage any added files before using the flake:

```sh
git add .
# On the configured host (substitute pve1 or pve2 as needed):
sudo nixos-rebuild switch --flake .#pve0
```

## pve0

- DHCP on `enp2s0`, MAC `fc:3f:db:10:c6:c9`; hostname `pve0`.
- Verified after reboot at `192.168.2.34`, resolved by the router as `pve0.home`.
  This is a DHCP lease, not a fixed address.
- Key-only SSH and passwordless sudo verified from the laptop; no failed units.
- NVMe `HFM256GD3GX013N-SKhynix`, serial `FYB3N06461330411F`:
  GPT, 1 GiB FAT32 `/boot`, remaining space ext4 `/`.
- `/srv/volumes` shares the root filesystem.
- HDD `HGST HTS721010A9E630`, serial `JR1004BNK14S5M`:
  previous Ceph/LVM and partition metadata removed; left blank for future Ceph.
- UEFI boot using systemd-boot; no swap.

Discovery fallback: `nmap -sn -PS22 192.168.2.0/24`. Verified that nmap reports
`pve0.home (192.168.2.34)`. Hostname display depends on DNS. If nmap is not
installed, use `nix shell nixpkgs#nmap` first.

Avahi also advertises `pve0.local`; resolution requires an mDNS-capable client on
the same LAN. This laptop currently uses the router's DNS (`pve0.home`), not an
mDNS resolver. No laptop networking configuration was changed.

Installed configuration lives at `/etc/nixos` on pve0. To rebuild there:

```sh
sudo nixos-rebuild switch --flake /etc/nixos#pve0
```
