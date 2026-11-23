---
icon: lucide/hard-drive
---

# Disk replacement

<span class="status status--planned">Not rehearsed</span>

Swap a failed Ceph HDD. This is an outline; write down the exact commands the
first time you do it.

## Before you start

- Only one disk is out. With two hosts' disks gone, I/O has already stopped.
- A replacement 2.5" SATA disk, and time for an extended SMART test (hours).

## Steps

1. **Take the OSD out** so Ceph re-creates its copies elsewhere:

    ```sh
    sudo ceph osd out <id>
    sudo ceph -s                  # wait until backfill is done
    ```

    With three hosts, the third copy can only come back on the new disk; until
    then the cluster runs on two copies.

2. **Stop and remove the old OSD:**

    ```sh
    sudo systemctl stop ceph-osd-<id>
    sudo ceph osd purge <id> --yes-i-really-mean-it
    ```

3. **Swap the disk** (host maintenance: drain its VMs, power off).
4. **Qualify the new disk:**

    ```sh
    sudo smartctl -t long /dev/disk/by-id/ata-<new-serial>
    sudo smartctl -a /dev/disk/by-id/ata-<new-serial>      # after it finishes
    ```

    Any reallocated or pending sectors, or a failed test: don't use it.

5. **Update `inventory.nix`:** the host's `hdd` path and, for a new OSD, its
   `osd.id` and `osd.uuid`. Commit and deploy the host.
6. **Create the OSD.** `scripts/ceph-bootstrap.sh osd` holds the exact
   checks and `ceph-volume` commands used for the first OSDs (serial, blank
   media, SMART, a typed `wipe`), but it was written for a new cluster and has
   not been tested for a replacement. It walks all hosts and skips OSDs that
   already exist. Read that phase first, then run it or repeat its
   `ceph-volume lvm prepare` and `activate` commands by hand on that host.

7. **Wait** for backfill to finish and `HEALTH_OK`.

## Check it worked

```sh
sudo ceph osd tree      # one up/in OSD per host
sudo ceph -s            # HEALTH_OK, all PGs active+clean
```

## Related

- [Ceph](../concepts/ceph.md) · [Hosts → Disk health](../concepts/hosts.md#disk-health)
