---
icon: lucide/power
---

# Host maintenance

Reboot, update or open up a host without an outage. One host at a time.

## Before you start

- `labctl health` is all `ok`, or only warns about something you know.
- A token with `manage` scope (host maintenance can reboot a host).

!!! warning "Not yet run live"

    `labctl host maintenance` and `resume` are tested, but haven't taken a real
    host down yet. They also need the Ceph key `client.clusterd` to be allowed
    `osd set-group` and `osd unset-group`; without that, maintenance stops at
    the `noout` step with the VMs already stopped (run `labctl host resume` to
    undo). Grant it once on any host, output discarded because it prints the
    key:

    ```sh
    sudo ceph auth caps client.clusterd mon 'allow r, allow command "osd set-group", allow command "osd unset-group"' mgr 'allow r' >/dev/null
    ```

    Until the first real run, keep the manual steps below at hand.

## Steps

1. **Take the host out**, and reboot it if that's the work:

    ```sh
    labctl host maintenance hgd1-hv01 --dry-run    # what will happen
    labctl host maintenance hgd1-hv01 --reboot     # or without --reboot for hardware work
    ```

    clusterd on that host checks that it's safe (no other host in
    maintenance, every node elsewhere Ready, etcd keeps quorum, and Ceph's own
    `ok-to-stop` for its OSDs), then drains and stops its VMs, agents first,
    and sets `noout` for that host's OSDs only, so Ceph doesn't start moving
    data. With `--reboot` the host reboots right after.

2. **Do the work.** For hardware, power it off now (`ssh jurre@10.10.20.11 'sudo
   poweroff'`) and back on after. `labctl status host` shows it as
   `Up,Maintenance` once it's back.
3. **Bring it back:**

    ```sh
    labctl host resume hgd1-hv01
    ```

    Starts its VMs if they aren't running, waits for each node to be Ready
    and uncordons it, lifts `noout` and waits until all PGs are clean.

4. **Check** before touching the next host: `labctl health`.

The S3, API and monitoring VIPs and the tunnel move to or keep using the
other hosts by themselves.

## Check it worked

`labctl health` is all `ok`: every host `Up` (no `Maintenance`), every node
Ready and uncordoned, Ceph `HEALTH_OK`, one owner per VIP.

??? note "Without the API: the same by hand"

    ```sh
    kubectl drain hgd1-k8w01 --ignore-daemonsets --delete-emptydir-data
    kubectl drain hgd1-k8m01 --ignore-daemonsets --delete-emptydir-data
    ssh jurre@10.10.20.12 'sudo ceph osd set-group noout hgd1-hv01'
    ssh jurre@10.10.20.11 'sudo systemctl reboot'
    # once it's back:
    ssh jurre@10.10.20.12 'sudo ceph osd unset-group noout hgd1-hv01'
    kubectl uncordon hgd1-k8m01 hgd1-k8w01
    ```

## Related

- Restarting only VMs: [Restart k3s nodes](../how-to/restart-k3s-nodes.md)
- Updating packages: [Update dependencies](../how-to/update-dependencies.md)
