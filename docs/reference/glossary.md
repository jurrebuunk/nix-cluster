---
icon: lucide/book-a
---

# Glossary

Terms these docs use. Most also show a tooltip when you hover over them on
any page.

agenix
:   Stores secrets in Git encrypted with age to SSH keys; hosts decrypt them
    at activation.

Agent (k3s)
:   A worker node: runs pods, no control plane or etcd.

Bootstrap server
:   The k3s server that creates a new cluster with `--cluster-init`
    (`inventory.k3s.bootstrapServer`).

Ceph
:   Distributed storage that keeps several copies of data across hosts.

CRUSH
:   Ceph's placement algorithm; here it puts each copy on a different host.

DNS-01
:   An ACME challenge that proves domain ownership through a DNS TXT record,
    so certificates need no open port.

etcd
:   The key-value store holding Kubernetes state, embedded in the k3s servers.
    Needs a majority (2 of 3) to work.

Generation
:   One NixOS system build. You can boot or roll back to an older one.

Inventory
:   `inventory.nix`, the single source of truth for addresses, disks and keys.

microVM
:   A small QEMU VM defined in Nix with [microvm.nix](https://github.com/microvm-nix/microvm.nix).

`noout`
:   A Ceph flag that stops it from rebalancing data while an OSD is briefly
    down for maintenance.

OSD
:   Object Storage Daemon: the Ceph process that stores data on one disk.

PG
:   Placement group: the unit Ceph distributes and recovers.

RBD
:   RADOS Block Device: a virtual disk stored in Ceph.

RGW
:   RADOS Gateway: Ceph's S3-compatible service.

Server (k3s)
:   A control-plane node with an etcd member. This cluster has three.

Split tunnel (Include mode)
:   WARP sends only listed ranges (`10.10.0.0/16`) through Cloudflare;
    everything else goes direct.

TAP
:   A virtual NIC that connects a VM to a host bridge.

Tunnel (Cloudflare)
:   An outbound-only connection from `cloudflared` on the hosts to Cloudflare
    that carries remote-access traffic.

VIP
:   A floating IP that Keepalived moves to a healthy machine: `10.10.30.10`
    (S3) and `10.10.40.10` (k3s API).

VLAN
:   A separate network on shared cables. The third octet of each site address
    is its VLAN ID.

VRRP
:   The protocol Keepalived uses to agree which machine holds a VIP.

WARP
:   Cloudflare's device client (Cloudflare One) used for remote access.

Zone
:   The `topology.kubernetes.io/zone` label: the physical host a node runs on.
