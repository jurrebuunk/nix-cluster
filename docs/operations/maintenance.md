# Maintenance

Planned work on a host or VM: updates, reboots, hardware changes. Always one
host at a time.

## Rebooting or servicing a host

A host runs a Ceph monitor and OSD, possibly the S3 VIP, a tunnel connector
and up to two k3s VMs. Taking it down is safe if the other two are healthy.

1. **Check health** ([five-minute check](index.md#health-check-in-five-minutes)).
   Don't start if anything is already degraded.
2. **Move the VMs' work away.** Drain the k3s nodes on that host:

    ```sh
    kubectl drain hgd1-k8w01 --ignore-daemonsets --delete-emptydir-data
    kubectl drain hgd1-k8m01 --ignore-daemonsets --delete-emptydir-data
    ```

    The VMs shut down with the host and start again on boot. Only take a
    server's host down while all three servers are members; while the
    cluster has two servers, that stops the API.

3. **Tell Ceph not to rebalance** while the OSD is briefly gone:

    ```sh
    ssh jurre@10.10.20.12 'sudo ceph osd set noout'      # from another host
    ```

4. **Do the work:** `ssh jurre@10.10.20.11 'sudo systemctl reboot'`, or
   power off for hardware.
5. **Wait for it to return:** SSH works, its monitor is back in quorum and its
   OSD is `up` (`sudo ceph -s`).
6. **Undo the flags:**

    ```sh
    ssh jurre@10.10.20.11 'sudo ceph osd unset noout'
    kubectl uncordon hgd1-k8m01 hgd1-k8w01
    ```

7. **Wait for `HEALTH_OK`** and Ready nodes before the next host.

The S3 VIP and the tunnel move to or keep using the other hosts by themselves.

## Restarting VMs after a deploy

```sh
scripts/k3s-roll.sh                # every enabled VM, agents first
```

See [k3s → Rolling restarts](../compute/k3s.md#rolling-restarts) for what it
checks.

## Updating everything

1. `nix flake update`, review `flake.lock`, then validate and commit.
2. Deploy hv01, verify, then hv02, then hv03
   ([Change and deploy](../hosts/deploy.md)).
3. If a new kernel came in, reboot each host using the procedure above.
4. `scripts/k3s-roll.sh` to boot the VMs on the new packages.

## Router and switch

- **Before any change:** export the configuration to
  `~/.local/state/nix-cluster/network-rollout/` with a timestamp in the name,
  mode 0600.
- **OPNsense updates:** System → Firmware. It snapshots a boot environment
  before upgrading; take a config backup anyway. The site loses its internet
  and inter-VLAN routing while it reboots; Ceph (storage VLAN) keeps working.
- **Switch:** a reboot interrupts everything, including Ceph traffic. Plan it.
  Save the config (`write memory`) before rebooting. The firmware update to
  something newer than `YA.16.02.0012` is still open.

## Disk replacement (HDD)

Not yet rehearsed. Outline:

1. `ceph osd out <id>`, wait for the data to move to the other two hosts
   (and accept the cluster is down to two copies until the new disk is in).
2. Stop the OSD, swap the disk, update `hdd` and `osd` in `inventory.nix`.
3. Check SMART, run an extended test, and create the new OSD with the OSD
   phase of `scripts/ceph-bootstrap.sh`.
4. Wait for backfill to finish and `HEALTH_OK`.

Write the exact commands down here when you do it the first time.

## Periodic checks

| How often | What |
| --- | --- |
| Weekly | The five-minute health check |
| Monthly | `smartctl -a` on every HDD; disk usage (`ceph df`); `nix flake update` |
| Every few months | Restore test: decrypt the latest backups; test that remote access works with one host stopped |
| Yearly | Rotate the Cloudflare and S3 credentials; review the Gateway rules |
