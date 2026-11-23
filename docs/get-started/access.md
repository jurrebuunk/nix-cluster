---
icon: lucide/log-in
---

# Get access

Connect to the site, log in to a host and a VM, and point `kubectl` at the
cluster.

## Connect WARP

Unless you're plugged into the site network, connect the Cloudflare One
(WARP) client first:

```sh
warp-cli connect
warp-cli status          # Connected
```

Only `10.10.0.0/16` goes through WARP; the rest of your traffic is
unaffected. On the users VLAN at home, disconnect it instead, so site traffic
goes straight through the router. Details: [Remote access](../concepts/remote-access.md).

??? note "Enrolling a new device"

    On NixOS: `services.cloudflare-warp.enable = true;`, rebuild, then
    `warp-cli registration new buunk`. On other systems, install the
    Cloudflare One app and log in to team `buunk`. Only allowed email
    addresses can enrol.

## Host login

```sh
ssh jurre@10.10.20.11              # hgd1-hv01
ssh jurre@hgd1-hv02.lan.buunk.org  # names work too
```

Key-only, no root login, passwordless `sudo` for `jurre`. Check it's healthy:

```sh
ssh jurre@10.10.20.11 'hostname; systemctl is-system-running; sudo ceph health'
```

## VM login

```sh
ssh jurre@10.10.40.11              # hgd1-k8m01
```

The same rules apply. All addresses are in [Addresses](../reference/addresses.md).

## Get a kubeconfig

```sh
scripts/kubeconfig.sh
kubectl get nodes -L topology.kubernetes.io/zone
```

This writes `~/.kube/hgd1.yaml` (mode 600), which the dev shell already uses
as `KUBECONFIG`. It points at `https://k8s.lan.buunk.org:6443`.

!!! danger "Cluster-admin"

    The kubeconfig grants full rights. Never commit it, paste it or copy it to
    a shared machine.

## Without WARP

At the site, plug into **switch port 1** (management VLAN, DHCP). From there
everything internal is reachable, including the router at
`ssh root@10.10.10.1`. The OPNsense console also always works.
