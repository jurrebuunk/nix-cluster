# nix-cluster

Minimal NixOS 26.05 configs for `pve0`, `pve1`, and `pve2` (x86_64).

- Shared config: `hosts/common.nix`
- Per-host config: `hosts/<host>/default.nix`
- SSH: `ssh jurre@<host-ip>` using this laptop's `~/.ssh/id_ed25519`
- Key-only SSH; root SSH disabled; `jurre` has passwordless sudo.

## Before installing each host

The hardware files are placeholders. These configs are **not bootable yet**.
We will choose disks and a bootloader separately for each host. Replace that
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

No partitioning or installation has been performed.
