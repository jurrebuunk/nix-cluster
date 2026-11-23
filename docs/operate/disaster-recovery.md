---
icon: lucide/siren
---

# Disaster recovery

<span class="status status--planned">Not rehearsed</span>

Bringing back a lost host, or the whole site. Rehearse before you need it,
and write down what you learn here.

## What you need

- This repo (GitHub).
- My laptop SSH key; it decrypts every agenix secret.
- The [state outside Git](index.md#state-outside-git): router and switch
  backups, encrypted Ceph keyring and TLS backups, tunnel credentials.

## Reinstall a host

For a dead NVMe or a broken OS on one host:

1. **Install NixOS** with UEFI and systemd-boot on the NVMe. Leave the HDD
   alone.
2. **Hardware config:** copy the new `hardware-configuration.nix` into
   `hosts/<host>/`. Keep `system.stateVersion` and the bootloader settings;
   don't import the installer's `configuration.nix`.
3. **Host key:** put the new public key in `inventory.nix` and re-encrypt the
   secrets ([Manage secrets → Re-key](../how-to/manage-secrets.md#re-key)).
4. **Deploy** with `deploy`. Use `TARGET=<temporary address>` if it
   isn't on its static address yet.
5. **Ceph:** its monitor store and keyrings were on the NVMe, so they're gone.
   Set `noout`, remove and re-add its monitor, and bring its OSD back with the
   keyring from the encrypted backup, or recreate the OSD and let Ceph
   backfill. Plan this before starting.
6. **VMs:** their disks were on the NVMe too. `kubectl delete node` the old
   nodes; the VMs start fresh and rejoin. Pin their new host keys.

## Rebuild the site

Each step depends on the one before:

1. **Network:** restore the router and switch with [`hgd1-network`](https://github.com/jurrebuunk/hgd1-network) (backups or a
   fresh run), after the by-hand bootstrap in [Rebuild the network](rebuild-network.md).
2. **Hosts:** install NixOS on all three and deploy this repo (new host keys
   mean re-encrypting the secrets).
3. **Ceph:** a new cluster with `ceph-bootstrap`, or restore its
   identity from the keyring backups if the HDDs survived.
4. **Remote access** works as soon as one host has the tunnel secret.
5. **k3s:** the VMs come up with the hosts. Set `k3s.bootstrapServer` back to
   `hgd1-k8m01` so it creates a new cluster, then set it to `null` again once
   all three servers have joined ([k3s → Joining](../concepts/k3s.md#joining)).
6. **Cluster components and apps** come back through Flux from `hgd1-k8s`, then **data** from backups.

!!! danger "Replication is not a backup"

    Data that only existed in Ceph or on VM disks is only as safe as its
    backups. Three copies protect against a failed disk, not against deleting
    a bucket or losing the site.
