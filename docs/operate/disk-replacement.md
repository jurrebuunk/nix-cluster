---
icon: lucide/hard-drive
---

# Disk replacement

<span class="status status--planned">Not rehearsed</span>

Swap a failed Ceph HDD. This is an outline; write down the exact commands the
first time you do it.

## Before you start

- Only one disk is out (`labctl disk list`: which drive, its SMART state;
  `labctl ceph status`: which OSD is down). With two hosts' disks gone, I/O
  has already stopped.
- A replacement 2.5" SATA disk, and time for an extended SMART test (hours).

## Steps

1. **Take the OSD out** so Ceph re-creates its copies elsewhere:

    ```sh
    ssh jurre@<host> 'sudo ceph osd out <id>'
    labctl ceph status            # wait until all PGs are clean again
    ```

    With three hosts, the third copy can only come back on the new disk; until
    then the cluster runs on two copies.

2. **Stop and remove the old OSD:**

    ```sh
    sudo systemctl stop ceph-osd-<id>
    sudo ceph osd purge <id> --yes-i-really-mean-it
    ```

3. **Swap the disk:** `labctl host maintenance <host>`, power off, swap,
   power on, and `labctl host resume <host>` after the next steps.
4. **Qualify the new disk:**

    ```sh
    sudo smartctl -t long /dev/disk/by-id/ata-<new-serial>
    sudo smartctl -a /dev/disk/by-id/ata-<new-serial>      # after it finishes
    ```

    Any reallocated or pending sectors, or a failed test: don't use it.

5. **Update `inventory.nix`:** the host's `hdd` path and, for a new OSD, its
   `osd.id` and `osd.uuid`. Commit and deploy the host.
6. **Create the OSD.** `ceph-bootstrap osd` holds the exact
   checks and `ceph-volume` commands used for the first OSDs (serial, blank
   media, SMART, a typed `wipe`), but it was written for a new cluster and has
   not been tested for a replacement. It walks all hosts and skips OSDs that
   already exist. Read that phase first, then run it or repeat its
   `ceph-volume lvm prepare` and `activate` commands by hand on that host.

7. **Wait** for backfill to finish and `HEALTH_OK`.

## Check it worked

```sh
labctl ceph status  # HEALTH_OK, 3/3 up and in, all PGs clean
labctl disk list    # the new drive: its serial, osd.<id>, SMART OK
```

## Related

- [Ceph](../concepts/ceph.md) · [Hosts → Disk health](../concepts/hosts.md#disk-health)
