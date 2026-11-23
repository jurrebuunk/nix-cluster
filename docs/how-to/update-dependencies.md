---
icon: lucide/package
---

# Update dependencies

Update nixpkgs, microvm.nix or agenix as a change of its own.

## Before you start

Run the [health check](../operate/index.md); don't update a degraded cluster.

## Steps

1. **Update the lock file:**

    ```sh
    nix flake update              # or: nix flake update nixpkgs
    git diff -- flake.lock
    ```

2. **Validate and commit** as in [Deploy a change](deploy.md).
3. **Deploy** hv01, verify, then hv02, then hv03.
4. **New kernel?** Reboot each host one at a time with
   [Host maintenance](../operate/host-maintenance.md).
5. **Boot the VMs** on the new packages:

    ```sh
    scripts/k3s-roll.sh
    ```

## Check it worked

```sh
for h in 11 12 13; do ssh jurre@10.10.20.$h 'echo "$(hostname) $(nixos-version)"'; done
kubectl get nodes -o wide
```

## Good to know

- `flake.nix` follows NixOS 26.05. Moving to the next release is a planned
  upgrade, not a routine update.
- Never bump `system.stateVersion` because of an update. It sets
  compatibility defaults for existing data, not the installed version.
