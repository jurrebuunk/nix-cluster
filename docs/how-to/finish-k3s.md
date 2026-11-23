---
icon: lucide/circle-plus
---

# Finish the cluster

<span class="status">Done 2026-11-23</span>

How the third server `hgd1-k8m02` was added after enabling VT-x on hv02, and
how the failover was proven. Kept as a record and as the pattern for adding
a server to a host that couldn't run VMs before.

## Before you start

- Physical access to hv02 (monitor and keyboard).
- The [health check](../operate/index.md) passes.

## Steps

1. **Enable VT-x on hv02.**

    ```sh
    ssh jurre@10.10.20.11 'sudo ceph osd set noout'
    ssh jurre@10.10.20.12 'sudo systemctl poweroff'
    ```

    In the BIOS, enable Intel Virtualization Technology (VT-x), save and boot.

    ```sh
    ssh jurre@10.10.20.12 'ls -l /dev/kvm'
    ssh jurre@10.10.20.11 'sudo ceph osd unset noout; sudo ceph -s'
    ```

    Wait for `HEALTH_OK`.

2. **Enable the VM.** In `inventory.nix` set
   `hosts.hgd1-hv02.kvmAvailable = true` and `vms.hgd1-k8m02.enabled = true`.
   Commit and deploy:

    ```sh
    scripts/deploy.sh hgd1-hv02 switch
    ```

    Pin its host key as in [Manage VMs](manage-vms.md#add-a-vm).

3. **Check three etcd members:**

    ```sh
    kubectl get nodes      # three nodes with control-plane,etcd
    ```

4. **Retire the bootstrap flag.** Set `k3s.bootstrapServer = null`, commit,
   deploy hv01.
5. **Prove failover.** In one terminal:

    ```sh
    while true; do kubectl get --raw=/readyz && echo; sleep 1; done
    ```

    In another:

    ```sh
    scripts/k3s-roll.sh hgd1-k8m01
    ```

    The first terminal must keep printing `ok` while k8m01 restarts and the
    VIP moves.

## Check it worked

- Five Ready nodes with zone labels, three of them `control-plane,etcd`.
- The API stayed reachable during step 5.

Result on 2026-11-23: five Ready nodes, three etcd members, and 41 of 41 API
checks succeeded while `hgd1-k8m01` restarted; the VIP moved to `hgd1-k8m02`.
