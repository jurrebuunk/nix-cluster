---
icon: lucide/box
---

# Manage VMs

Add, move or remove a VM. VMs exist only through `inventory.nix`; never
create one by hand. Background: [VMs](../concepts/vms.md).

## Before you start

- The owning host has KVM (`kvmAvailable = true`).
- The host has room: at most 11 GiB of VM memory per host.
- For k3s nodes you have a [kubeconfig](../get-started/access.md#get-a-kubeconfig).

## Add a VM

1. Add an entry under `vms` in `inventory.nix`:

    ```nix
    hgd1-k8w03 = {
      host = "hgd1-hv02"; enabled = true; id = 23; role = "agent";
      vcpu = 4; memMB = 4096; diskGB = 60;
      ip = { k8s = "10.10.40.23"; storage = "10.10.30.33"; };
    };
    ```

    Pick a new, unique `id` (it fixes the MACs) and two free IPs.

2. Validate: `nix flake check --no-build` catches collisions and the memory
   limit.
3. Commit and deploy the owning host. The VM starts and, for k3s roles, joins
   the cluster on its own.
4. Pin its SSH host key, read from the trusted host:

    ```sh
    ssh jurre@10.10.20.12 'sudo journalctl -u microvm@hgd1-k8w03 -o cat | grep VM_HOST_KEY'
    ```

    Copy the key into the entry as `hostKey = "ssh-ed25519 …";` and commit.

5. Optional: add a DNS override on OPNsense (`hgd1-k8w03.lan.buunk.org`).

Keep an odd number of k3s servers.

## Move a VM

1. For a k3s node, drain it and delete the node object:

    ```sh
    kubectl drain hgd1-k8w02 --ignore-daemonsets --delete-emptydir-data
    kubectl delete node hgd1-k8w02
    ```

2. Stop it and confirm it's stopped: `scripts/vm.sh hgd1-k8w02 stop`.
3. Change `host` in the inventory. Commit. Deploy the **old** host first, then
   the new one.
4. The disk image doesn't move. Either copy
   `/var/lib/microvms/<name>/var-lib.img` while the VM is stopped, or start
   fresh and let it rejoin. **Never run two copies of one image.**
5. Once it works, delete the old directory on the old host.

The zone label is only set when a node registers; that's why the node object
has to be deleted.

## Remove a VM

1. For a k3s node: drain and delete it as above.
2. Set `enabled = false` (or delete the entry), commit, deploy the host.
3. The disk image stays in `/var/lib/microvms/<name>/` until you delete it.

## Check it worked

```sh
scripts/vm.sh list
kubectl get nodes -L topology.kubernetes.io/zone
```

!!! note "Disk size"

    `diskGB` only applies when the image is created. Changing it later doesn't
    resize the image. Never shrink an existing filesystem.
