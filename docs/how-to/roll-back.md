---
icon: lucide/rotate-ccw
---

# Roll back

Return a host to its previous system after a bad deploy.

## Before you start

Know which host is affected and whether you can still reach it over SSH.

## Steps

=== "Host still reachable"

    ```sh
    ssh jurre@10.10.20.11 'sudo nixos-rebuild switch --rollback'
    ```

=== "Host not reachable"

    1. Go to the host's console (monitor and keyboard).
    2. Reboot and pick the previous generation in the systemd-boot menu.

Then, in both cases:

1. Revert the change in Git: `git revert <commit>`.
2. Validate and deploy the fixed version ([Deploy a change](deploy.md)). A
   rollback on the host doesn't change the repo; the next deploy would
   bring the bad change back.

## Check it worked

```sh
labctl host list                                                     # the host is Up again
labctl metrics query 'node_systemd_unit_state{state="failed"} == 1'  # (no data)
ssh jurre@10.10.20.11 'readlink /run/current-system'                 # which generation runs
```

!!! warning "Generations are not backups"

    A rollback restores the system configuration, not data. It doesn't undo
    changes to VM disks, Ceph, databases or anything else on disk. Don't
    delete known-good generations until the replacement is verified.

## Risky network changes

For a change that could cut a host off the network, arm the self-reverting
guard before deploying. It boots the old generation if you don't confirm
within ten minutes. See
[Rebuild the network → Moving a host](https://jurrebuunk.github.io/hgd1-network/rebuild/#moving-a-host).
