---
icon: lucide/git-commit-horizontal
---

# Your first change

A guided first deploy: add a small package to every host, deploy it to one
host, check it, then roll it out. It shows the loop you'll use for every
change.

**Before you start:** [access](access.md) works, and `git status` is clean.

## 1. Make the change

Open `hosts/common.nix` and add a package that's harmless to have, for
example `htop`:

```nix
environment.systemPackages = [ pkgs.htop ];
```

`hosts/common.nix` applies to all three hosts. Add `pkgs` to the argument
header if it isn't there: `{ config, lib, pkgs, inventory, ... }:`.

## 2. Validate

```sh
git add -A
nix flake check --no-build
nix build --no-link .#nixosConfigurations.hgd1-hv01.config.system.build.toplevel
```

The first command evaluates every host and VM and runs the inventory checks.
The second builds hv01's full system without activating it.

## 3. Commit

```sh
git commit -m "Add htop to the hosts"
```

The deploy script refuses uncommitted changes, so every deployed system
matches a commit.

## 4. Deploy one host

```sh
scripts/deploy.sh hgd1-hv01 dry-activate
scripts/deploy.sh hgd1-hv01 switch
```

The preview lists what would change. Note the line
`would NOT stop the following changed units: microvm@…` if a VM changed:
deploys never restart VMs.

## 5. Check it

```sh
ssh jurre@10.10.20.11 'which htop; systemctl is-system-running; systemctl --failed --no-pager'
```

## 6. Roll out

Repeat steps 4 and 5 for `hgd1-hv02`, then `hgd1-hv03`. Never deploy to
two hosts at the same time.

## 7. Push

```sh
git push
```

## Undo it

Revert the commit and deploy again the same way. If a host is in trouble,
see [Roll back](../how-to/roll-back.md).

## What you learned

- [x] Changes go through the repo, never by hand on a host.
- [x] `nix flake check` catches mistakes before anything is deployed.
- [x] One host at a time, checked before the next.

Next: [Tour of the repo :octicons-arrow-right-24:](repository.md)
