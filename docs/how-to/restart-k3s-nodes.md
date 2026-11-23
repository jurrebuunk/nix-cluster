---
icon: lucide/refresh-cw
---

# Restart k3s nodes

Restart k3s VMs one at a time without losing etcd quorum or workloads. Use it
after a deploy (deploys never restart VMs) and for any planned VM restart.

## Before you start

- A [kubeconfig](../get-started/access.md#get-a-kubeconfig).
- Every enabled VM is a Ready node: `kubectl get nodes`.

## Steps

```sh
scripts/k3s-roll.sh                 # every enabled VM, agents first
scripts/k3s-roll.sh hgd1-k8w01      # or just one
```

For each VM the script:

1. Refuses to continue unless every enabled VM is a Ready node.
2. Drains it (`--ignore-daemonsets --delete-emptydir-data`, 5 minutes).
3. Restarts the VM through `vm.sh`.
4. Waits up to 10 minutes for a **new boot** of that node to be Ready.
5. Uncordons it and checks the API.

From `clusterd` `v1.0`, a single node can also be restarted with the CLI,
which runs the same sequence through the [Platform API](../concepts/api.md):

```sh
labctl vm restart hgd1-k8w01
```

## Check it worked

```sh
kubectl get nodes -L topology.kubernetes.io/zone
```

All nodes are `Ready` and none shows `SchedulingDisabled`.

## If it stops

- **Drain refused:** bare pods without a controller block the drain on
  purpose. Delete or fix them, then run it again.
- **Node didn't come back:** it stays cordoned. Look at
  [Troubleshooting → k3s node](../operate/troubleshooting.md#k3s-node-not-ready),
  fix it, then `kubectl uncordon <node>`.
