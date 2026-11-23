---
icon: lucide/power
---

# Host maintenance

Reboot, update or open up a host without an outage. One host at a time.

## Before you start

A host runs a Ceph monitor and OSD, maybe the S3 VIP, a tunnel connector and
up to two k3s VMs. Taking it down is safe only if the other two are healthy:

- The [health check](index.md#health-check) passes.
- All three k3s servers are members. While there are only two, taking down a
  server's host stops the API ([Finish the cluster](../how-to/finish-k3s.md)).

## Steps

1. **Drain the host's k3s nodes** (here hv01's):

    ```sh
    kubectl drain hgd1-k8w01 --ignore-daemonsets --delete-emptydir-data
    kubectl drain hgd1-k8m01 --ignore-daemonsets --delete-emptydir-data
    ```

2. **Stop Ceph rebalancing** while the OSD is briefly gone:

    ```sh
    ssh jurre@10.10.20.12 'sudo ceph osd set noout'
    ```

3. **Do the work:** `ssh jurre@10.10.20.11 'sudo systemctl reboot'`, or power
   off for hardware. Its VMs shut down with it and start again at boot.
4. **Wait for it to return:** SSH works, its monitor is in quorum, its OSD is
   `up`:

    ```sh
    ssh jurre@10.10.20.11 'sudo ceph -s'
    ```

5. **Undo the flags:**

    ```sh
    ssh jurre@10.10.20.11 'sudo ceph osd unset noout'
    kubectl uncordon hgd1-k8m01 hgd1-k8w01
    ```

6. **Wait for `HEALTH_OK`** and Ready nodes before touching the next host.

The S3 VIP and the tunnel move to or keep using the other hosts by themselves.

## Check it worked

The [health check](index.md#health-check) passes: `HEALTH_OK`, every node
Ready and uncordoned, exactly one S3 VIP owner, no `noout` flag.

## Related

- Restarting only VMs: [Restart k3s nodes](../how-to/restart-k3s-nodes.md)
- Updating packages: [Update dependencies](../how-to/update-dependencies.md)
