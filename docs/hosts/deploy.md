# Change and deploy

Every change follows the same loop: edit, validate, commit, deploy one host,
verify, then the next host. There is no CI for deployments; I deploy by hand
from the laptop, deliberately one host at a time.

## Before you start

- The laptop has the repo, my SSH key and the WARP client connected (or is on
  the site network). `ssh jurre@10.10.20.11` must work without a password.
- `nix develop` gives you `nixos-rebuild`, `agenix` and the rest.
- Check `git status`. Other work in progress must not end up in your deploy.

## 1. Edit and validate

Keep each change small and focused. Flakes only see files that Git knows
about, so stage new files:

```sh
git add -A
git diff --cached
nix flake check --no-build
nix build --no-link .#nixosConfigurations.hgd1-hv01.config.system.build.toplevel
```

`flake check --no-build` evaluates every host and VM, including all inventory
assertions, without building them. `nix build` builds one host's whole system
without activating it. For shared changes, build every affected host.

## 2. Commit

```sh
git commit -m "Describe the change"
```

`scripts/deploy.sh` refuses a dirty working tree, so what runs on a host
always matches a commit. Push regularly; GitHub is the off-site copy of this
repo.

## 3. Preview and deploy one host

```sh
scripts/deploy.sh hgd1-hv01 dry-activate     # build and show what would change
scripts/deploy.sh hgd1-hv01 switch           # activate now and make it the boot default
```

What the script does:

1. Reads the host's address and SSH host key from the inventory.
2. Refuses to continue if the host presents a different key, which would mean
   the wrong machine or a reinstalled one.
3. Runs `nixos-rebuild <action> --build-host <host> --target-host <host> --sudo --use-substitutes`.

The laptop only evaluates the flake; **the host builds its own system** and
downloads from the binary cache itself. The laptop's own Nix is never touched.

| Action | Effect |
| --- | --- |
| `dry-activate` | Build and print which units would restart; change nothing |
| `switch` | Activate now and boot into it from now on |
| `boot` | Boot into it next time; don't touch the running system |
| `test` | Activate now, but keep the old boot default |

`dry-activate` doesn't prove a change is safe; kernel changes only take
effect after a reboot. With SSH, firewall or network changes, keep a second
session open and know how you'd reach the console.

!!! note "VMs are never restarted by a host deploy"

    A deploy installs new VM runners but leaves running VMs alone. The preview
    shows `would NOT stop the following changed units: microvm@...`. Boot VMs
    into their new version with [`scripts/k3s-roll.sh`](../compute/k3s.md#rolling-restarts).

## 4. Verify, then the next host

```sh
ssh jurre@10.10.20.11 'hostname; nixos-version; systemctl is-system-running; systemctl --failed --no-pager'
ssh jurre@10.10.20.11 'sudo ceph health'
```

Also test the service you changed and read its logs, and open a **new** SSH
connection. Only then deploy the next host. Ceph and k3s stay available with
one host misbehaving, never with two.

## Rolling back

If the host is still reachable:

```sh
ssh jurre@10.10.20.11 'sudo nixos-rebuild switch --rollback'
```

If it doesn't boot or isn't reachable, pick the previous generation in the
systemd-boot menu at the console. Either way, revert the change in Git and
deploy again: a rollback on the host doesn't change the repo.

!!! warning "Generations are not backups"

    Rolling back restores the system configuration, not data. It doesn't undo
    changes to VM disks, Ceph, databases or anything else on disk.

## Updating dependencies

Do it as its own change:

```sh
nix flake update nixpkgs          # or microvm, agenix
git diff -- flake.lock
```

Then validate, commit and roll out host by host as usual. Afterwards, roll the
VMs so they boot the new packages too.

- `flake.nix` follows NixOS 26.05. Moving to the next release is a planned
  upgrade, not a routine update.
- Never bump `system.stateVersion` because of an update. It sets compatibility
  defaults for existing data, not the installed version.

## Remote environment variables

| Variable | Use |
| --- | --- |
| `TARGET=<addr>` | Connect to another address than the inventory's, e.g. a temporary DHCP lease during a rebuild |
| `JUMP=<user@addr>` | SSH through a jump host; only needed before remote access exists |
| `ALLOW_DIRTY=1` | Deploy uncommitted changes. Avoid it |
| `SSH_USER` | Log in as someone other than `jurre` |

## Why builds happen on the hosts

`jurre` is not a Nix trusted user on the hosts, so a host would refuse
unsigned closures built on the laptop. Building on the target avoids that.
Making the laptop do the builds would need signed closures or trusted-user
access, and trusted-user access is effectively root, so I've kept it this way.
