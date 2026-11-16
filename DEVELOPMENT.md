# Development and deployment

This repo is the source of truth for all three nodes. Work from
`/home/jurre/repos/nix-cluster` on the laptop, then deploy over SSH.
No deployment framework or CI is configured; deployments are manual.

## Where changes belong

| File | Purpose |
| --- | --- |
| `flake.nix` | Nixpkgs release and the three `nixosConfigurations` outputs |
| `flake.lock` | Exact dependency revision; keep it committed |
| `hosts/common.nix` | Settings shared by every node |
| `hosts/<host>/default.nix` | Hostname, bootloader, and node-specific settings/imports |
| `hosts/<host>/hardware-configuration.nix` | That node's disk UUIDs and detected hardware |

When a feature grows, create a reusable module such as `modules/monitoring.nix`
and import it from `hosts/common.nix` or selected host configs. For example,
a host can add `../../modules/monitoring.nix` to its existing `imports` list.
The `modules/` directory does not exist yet; nothing there is imported automatically.
Keep hardware configuration specific to its node.

## Normal workflow

Examples below use `pve0`. Run them from the laptop's repo directory.
The nodes must be online, and `ssh jurre@pve0.home` must work without a password.
The laptop needs Nix with flakes and `nixos-rebuild`; both are currently available.

### 1. Edit and validate

Make a small, focused change. Stage new files so the Git-backed flake can see
them, and review exactly what will be committed:

```sh
cd /home/jurre/repos/nix-cluster
git add .
git diff --cached
nix flake check --no-build
nix build --no-link .#nixosConfigurations.pve0.config.system.build.toplevel
```

`flake check --no-build` evaluates all three configurations but does not build
their systems or test running services. The `nix build` command builds the
selected node's system without activating it. For shared changes, also build
the other affected nodes before deploying to them.

Never stage passwords, private keys, or other secrets.

### 2. Commit

```sh
git commit -m "Describe the configuration change"
git status --short
```

Deploy with a clean working tree so the deployed configuration matches a
recorded commit. A local `.#pve0` deployment otherwise includes working-tree
changes, not just the latest commit. Keep a private Git remote or another
backup of this repo; no remote is set up by this workflow.

### 3. Preview and deploy one node

```sh
nixos-rebuild dry-activate \
  --flake .#pve0 \
  --build-host jurre@pve0.home --target-host jurre@pve0.home --sudo

nixos-rebuild switch \
  --flake .#pve0 \
  --build-host jurre@pve0.home --target-host jurre@pve0.home --sudo
```

The laptop evaluates this repo, sends the build inputs over SSH, and builds on
the selected node. Activation uses that node's passwordless sudo. Do not run
the laptop's rebuild without `--target-host`: that would target the laptop itself.

These examples deliberately build on the target: the current configs do not
grant `jurre` Nix daemon trusted-user access. `--sudo` handles activation, not
permission to import unsigned laptop-built closures. For laptop-side builds
later, first arrange signed closures and trusted keys, or explicitly grant
Nix trusted-user access using a target-built deployment. Nix trusted-user
access is effectively root-equivalent; do not disable signature checking.

- `dry-activate`: builds and previews activation changes; does not activate.
- `switch`: activates now and makes the generation the default for future boots.
- `boot`: prepares the generation for the next reboot without activating now.

A preview is not a full safety test. Kernel changes generally need a reboot.
Be especially careful with SSH, firewall, and networking changes; keep an
existing session open and arrange console access for risky changes.

### 4. Verify, then roll out

```sh
ssh jurre@pve0.home \
  'hostname; nixos-version; systemctl is-system-running; systemctl --failed --no-pager'
```

Also test the service you changed and check its logs. Confirm a new SSH
connection still works. If a reboot is needed, reboot this node and verify it
again before proceeding.

Only then deploy the same change to `pve1` and `pve2`, one at a time. Match the
flake output, build host, and target host: `.#pve1` goes to `jurre@pve1.home`,
not another node.
Once clustered services exist, respect their health and quorum requirements
before restarting or updating any node.

## Rollback

If SSH still works, return a node to its previous system generation:

```sh
ssh jurre@pve0.home 'sudo nixos-rebuild switch --rollback'
```

If it cannot boot or cannot be reached, use the console and choose a previous
NixOS generation in the systemd-boot menu. Revert the bad change in Git,
validate it, and redeploy; a server rollback does not revert this repo.

Generations are not data backups. Rollback does not undo volume contents,
filesystem changes, database migrations, or Ceph operations. Do not delete
known-good generations until the replacement has been verified.

## Dependency updates

Update deliberately, as a separate change:

```sh
nix flake update nixpkgs
git diff -- flake.lock
```

Then follow the normal validate, commit, and one-node-at-a-time rollout.
`flake.nix` currently follows NixOS 26.05; changing releases is a separate,
planned upgrade. Do not bump `system.stateVersion` merely because nixpkgs is
updated: it controls compatibility defaults, not the installed release.

## Repo versus files on the servers

`/etc/nixos` on each node is its installation-time snapshot. Remote deployment
activates a system built from the laptop repo; it does **not** synchronize that
directory or require the node to pull Git. Do not routinely rebuild from those
snapshots after adopting the laptop deployment workflow: they may be stale.
Avoid permanent manual edits on the servers; express them here instead.

Before adding Ceph or other cluster services, establish stable addresses
(e.g. DHCP reservations), finish disk testing, and plan backups. The HDDs are
currently blank and no Ceph services are configured. Add sops-nix or agenix
when secrets are needed rather than putting plaintext secrets in Git or Nix.
