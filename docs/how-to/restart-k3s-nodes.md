---
icon: lucide/refresh-cw
---

# Restart k3s nodes

Restart k3s VMs one at a time without losing etcd quorum or workloads. Use it
after a deploy (deploys never restart VMs) and for any planned VM restart.

## Before you start

- Every enabled VM is a Ready node: `labctl node list`.
- An API token with at least `operator` scope; no kubeconfig needed.

## Steps

```sh
labctl vm roll                      # every enabled VM, agents first, one at a time
labctl vm restart hgd1-k8w01        # or just one
```

For each VM, clusterd on the VM's host:

1. Refuses unless every *other* node is Ready, etcd keeps quorum and no pod
   without a controller would be lost (`412`, nothing changed).
2. Takes the cluster-wide lock, so nothing else restarts at the same time.
3. Cordons and drains it (respecting disruption budgets, 5 minutes).
4. Restarts `microvm@<vm>`.
5. Waits up to 10 minutes for a **new boot** of that node to be Ready.
6. Uncordons it and checks the Kubernetes API.

`vm roll` asks once, then restarts the VMs in turn and stops at the first
failure. It refuses when it can't see which nodes are servers.

## Check it worked

```sh
labctl node list
```

All nodes are `Ready` and none shows `SchedulingDisabled`.

## If it stops

- **Drain refused:** bare pods without a controller block the drain on
  purpose. Delete or fix them, then run it again.
- **Node didn't come back:** it stays cordoned. Look at
  [Troubleshooting → k3s node](../operate/troubleshooting.md#k3s-node-not-ready),
  fix it, then `labctl node uncordon <node>`.
