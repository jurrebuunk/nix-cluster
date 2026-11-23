---
icon: lucide/terminal
---

# Scripts

All scripts live in `scripts/`, run from anywhere in the repo, and read
addresses and keys from `inventory.nix`. They check SSH host keys against the
inventory before doing anything, and fetch `jq` or `kubectl` through
`nix shell` when they're missing.

## deploy.sh

Deploy one host.

```sh
scripts/deploy.sh <host> [switch|boot|test|dry-activate]     # default: switch
```

Refuses a dirty working tree and a host whose key differs from the inventory;
the host builds its own system. Environment: `TARGET`, `JUMP`, `ALLOW_DIRTY=1`,
`SSH_USER`. See [Deploy a change](../how-to/deploy.md).

## vm.sh

Look at or control one VM's systemd unit on its host.

```sh
scripts/vm.sh list
scripts/vm.sh <vm> [status|start|stop|restart|logs]
```

Never creates, moves or deletes disks, and doesn't drain Kubernetes. Refuses
VMs that are disabled in the inventory. See [VMs](../concepts/vms.md#operating).

## k3s-roll.sh

Restart k3s VMs one at a time without losing quorum or workloads.

```sh
scripts/k3s-roll.sh [vm...]       # default: all enabled VMs, agents first
```

Needs `KUBECONFIG`. Per VM: every node Ready → drain → restart → new boot
Ready → uncordon. Stops and leaves the node cordoned on any failure. See
[Restart k3s nodes](../how-to/restart-k3s-nodes.md).

## kubeconfig.sh

Write the cluster-admin kubeconfig to the laptop.

```sh
scripts/kubeconfig.sh [server-vm]     # default: first enabled server
```

Writes `~/.kube/hgd1.yaml` (or `KUBECONFIG_OUT`) with mode 600, context
`hgd1` and server `https://k8s.lan.buunk.org:6443`. Refuses a server whose
`hostKey` isn't pinned or doesn't match.

## ceph-bootstrap.sh

Create a new Ceph cluster. **Not** for disk replacement.

```sh
scripts/ceph-bootstrap.sh [check|mon|mgr|osd|pools|rgw|all]     # default: all
```

`check` is read-only. The OSD phase wipes HDDs only after strict SMART and
identity checks and a typed `wipe` confirmation. Every phase skips what
already exists. See [Ceph](../concepts/ceph.md#creating-a-cluster).
