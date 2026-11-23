---
icon: lucide/terminal
---

# Scripts

All scripts live in `scripts/`, run from anywhere in the repo, and read
addresses and keys from `inventory.nix`. They check SSH host keys against the
inventory before doing anything, and fetch `jq` or `kubectl` through
`nix shell` when they're missing.

VMs are started, stopped, restarted and rolled with `labctl vm`; there is no
script for that anymore (see [CLI reference](cli.md)).

## deploy.sh

Deploy one host.

```sh
scripts/deploy.sh <host> [switch|boot|test|dry-activate]     # default: switch
```

Refuses a dirty working tree and a host whose key differs from the inventory;
the host builds its own system. Environment: `TARGET`, `JUMP`, `ALLOW_DIRTY=1`,
`SSH_USER`. See [Deploy a change](../how-to/deploy.md).

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
