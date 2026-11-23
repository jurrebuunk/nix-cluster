# Development and deployment

This repo is the source of truth for all three nodes. Work from
`/home/jurre/repos/nix-hgd1-cluster` on the laptop, then deploy over SSH.
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
Modules in `modules/` are imported for every host from `flake.nix`. Cluster-wide
facts (addresses, disks, keys) live in `inventory.nix`.
Keep hardware configuration specific to its node.

## Normal workflow

Examples below use `hgd1-hv01`. Run them from the laptop's repo directory.
The nodes must be online, and `ssh jurre@10.10.20.11` must work without a password
(from outside the site: through Cloudflare WARP, see
[network/REMOTE-ACCESS.md](network/REMOTE-ACCESS.md)). Host IPs are static, see
`inventory.nix`. For the first deployment onto the VLAN network, follow
[ROLLOUT.md](ROLLOUT.md) instead.
`nix develop` provides the tools (nixos-rebuild, agenix, cloudflared, jq, …).

### 1. Edit and validate

Make a small, focused change. Stage new files so the Git-backed flake can see
them, and review exactly what will be committed:

```sh
cd /home/jurre/repos/nix-hgd1-cluster
git add .
git diff --cached
nix flake check --no-build
nix build --no-link .#nixosConfigurations.hgd1-hv01.config.system.build.toplevel
```

`flake check --no-build` evaluates all three configurations but does not build
their systems or test running services. The `nix build` command builds the
selected node's system without activating it. For shared changes, also build
the other affected nodes before deploying to them.

Never stage passwords, private keys, or other secrets in plain text. Secrets are
`secrets/*.age` files encrypted with agenix to the laptop key and every host key
(`secrets/secrets.nix`); edit them with `cd secrets && agenix -e <name>.age`.
After changing a host key in `inventory.nix`, run `agenix -r` there.

### 2. Commit

```sh
git commit -m "Describe the configuration change"
git status --short
```

Deploy with a clean working tree so the deployed configuration matches a
recorded commit. A local `.#hgd1-hv01` deployment otherwise includes working-tree
changes, not just the latest commit. Keep a private Git remote or another
backup of this repo; no remote is set up by this workflow.

### 3. Preview and deploy one node

```sh
scripts/deploy.sh hgd1-hv01 dry-activate
scripts/deploy.sh hgd1-hv01 switch
```

`scripts/deploy.sh` takes the address from `inventory.nix`, refuses a dirty
working tree, checks that the host's SSH key matches the inventory, and runs
`nixos-rebuild <action> --build-host <host> --target-host <host> --sudo
--use-substitutes`. `TARGET=<addr>` overrides the address and `JUMP=<user@addr>`
adds an SSH jump host.

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
ssh jurre@10.10.20.11 \
  'hostname; nixos-version; systemctl is-system-running; systemctl --failed --no-pager'
```

Also test the service you changed and check its logs. Confirm a new SSH
connection still works. If a reboot is needed, reboot this node and verify it
again before proceeding.

Only then deploy the same change to `hgd1-hv02` and `hgd1-hv03`, one at a time. Match the
`scripts/deploy.sh` always pairs the flake output with that host's address and
verifies its host key, so `.#hgd1-hv02` cannot land on another node.
Once clustered services exist, respect their health and quorum requirements
before restarting or updating any node.

## Rollback

If SSH still works, return a node to its previous system generation:

```sh
ssh jurre@10.10.20.11 'sudo nixos-rebuild switch --rollback'
```

If it cannot boot or cannot be reached, use the console and choose a previous
NixOS generation in the systemd-boot menu. Revert the bad change in Git,
validate it, and redeploy; a server rollback does not revert this repo.

Generations are not data backups. Rollback does not undo volume contents,
filesystem changes, database migrations, or Ceph operations. Do not delete
known-good generations until the replacement has been verified.

## VM deployment and lifecycle

Step 3 is live; see [VMS.md](VMS.md). Guests are built with their owning host
and kept on local NVMe. `scripts/vm.sh list` shows enabled versus reserved
inventory entries. With WARP connected, run `scripts/vm.sh hgd1-k8m01 status`
for the current test VM. Host deployments install updated runners but do not
restart guests; apply those changes through a deliberate per-VM restart.
Persistence/SSH identity and unchanged VM PID across host deployment were
verified. k3s drain/quorum operations are not implemented by the lifecycle CLI.

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

Remote deployment activates a system built from the laptop repo; it does
**not** create or synchronize `/etc/nixos` or require a node to pull Git.
That directory was absent on the current installations. If a snapshot exists
on a future installation, do not rebuild from it after adopting this workflow:
it may be stale.
Avoid permanent manual edits on the servers; express them here instead.

N5/N6 established and reboot-tested static addresses; 83/83 network checks
passed. Ceph step 2 completed on 2026-11-23 after all extended SMART tests
passed: the reserved HDDs now hold BlueStore OSDs, with three monitors/OSDs/RGWs
and replica 3/min_size 2. Real RBD/S3 operations survived each single-host Ceph
outage and all replicas recovered; hv02/hv03 rebooted, while hv01's VM stayed
running during service recovery. See [CEPH.md](CEPH.md) for tests, disk cautions
and encrypted recovery-key backups.

Never reboot during a future qualification test. Once Ceph is initialized,
maintain one host at a time and wait for HEALTH_OK before touching the next.
Use agenix for deployed secrets; runtime admin/S3 credentials and plaintext
backups do not belong in Git or the Nix store.

The S3 HA endpoint (step 2.1) is also live. `modules/s3-ha/` owns the private
VIP, proxies and automatic DNS-01 TLS; [S3-HA.md](S3-HA.md) covers validated
failover and certificate/credential handling. Proxy changes reload gracefully.
Changes to the VIP/firewall/Keepalived still require one-node-at-a-time rollout
and a check that exactly one host owns the VIP. Never use Ceph HEALTH_OK as the
VIP's liveness predicate: a single-host degraded cluster must remain usable.

### Module organization

- Keep function argument headers on one line, e.g.
  `{ config, lib, inventory, ... }:`. Preserve this convention if a formatter
  expands headers; it applies to host, guest and standalone Nix modules alike.
- Feature directories have an explicit `default.nix` entrypoint, not automatic
  directory scanning. Standalone focused modules can remain single files.
- `modules/s3-ha/` separates TLS, proxy, failover and firewall responsibilities.
  Each child retains its enable guard; `mkIf` does not conditionally import files.
- `modules/microvm/host/` separates runtime, validation and bridge networking;
  `modules/microvm/guest/` separates runtime/storage, networking and access.
- `lib/vm-network.nix` is a pure helper, not an imported NixOS module. Guest
  `vm`/`vmName` context comes from flake `specialArgs`, not hidden module arguments.
- Keep dependencies with their service and short embedded scripts/configuration
  with their feature. Avoid tiny wrapper files or abstractions just to save lines.

For a structure-only refactor, capture all eight
`nixosConfigurations.<name>.config.system.build.toplevel.outPath` values before
and after. Identical outputs mean no system behavior changed and no deployment
is needed. Also check the S3-disabled branch and negative inventory assertions.
