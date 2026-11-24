---
icon: lucide/network
---

# Host network

How the hosts and VMs sit on the site network: one cable per host, split
into VLANs and bridges by NixOS. The network itself (router, switch,
firewall between VLANs, DNS) has its own docs.

!!! network "On the network docs"

    The OPNsense router and Aruba switch, the VLAN design, the firewall policy between VLANs, DNS overrides and the Sunshine forwards.

    [Network design](https://jurrebuunk.github.io/hgd1-network/concepts/design/){ .md-button }

!!! info "At a glance"

    **Configured in** `modules/network.nix`, `modules/microvm/host/networking.nix`
    · **Addresses** `inventory.nix` → `vlans`, `hosts`, `vms`, and
    [Addresses](../reference/addresses.md) · **Ports**
    [Firewall](../reference/firewall.md)

## VLANs

The site uses `10.10.0.0/16`, and the third octet is always the VLAN ID.

| VLAN | Name | Subnet | Gateway | DHCP | What lives there |
| --- | --- | --- | --- | --- | --- |
| 10 | mgmt | `10.10.10.0/24` | `.1` | `.100–.199` | Router, switch |
| 20 | infra | `10.10.20.0/24` | `.1` | no | Hypervisors, `hgd1-gpu1` |
| 30 | storage | `10.10.30.0/24` | none | no | Ceph; **not routed** |
| 40 | k8s | `10.10.40.0/24` | `.1` | no | k3s VMs, API VIP `.10`, load balancers `.200–.249` |
| 100 | users | `10.10.100.0/24` | `.1` | `.100–.249` | Wired users, the gaming VM |

`10.42.0.0/16` and `10.43.0.0/16` stay free for k3s pods and services. The
storage VLAN never reaches the router: only hosts and VMs with a leg in it
can talk Ceph.

## Host wiring

Each hypervisor has one cable carrying VLAN 20 untagged and VLANs 30 and 40
tagged. NixOS turns that into:

```text
enp2s0                 10.10.20.1x/24   host management, default route
enp2s0.30 → br-stor    10.10.30.1x/24   Ceph and S3; VM storage NICs attach here
enp2s0.40 → br-k8s     (no address)     VM k8s NICs attach here
```

`br-k8s` has no host address on purpose: the host isn't reachable from the
k8s VLAN, and its firewall drops anything that would route between the
bridges and the rest of the host.


## VMs

Each k3s VM gets two NICs: one on `br-k8s` (VLAN 40, its node address and
default route) and one on `br-stor` (VLAN 30, to reach Ceph, S3 and the
monitoring stores without the router). Addresses and MACs come from the
inventory (`02:00:00:40:00:<id>` and `02:00:00:30:00:<id>`).

## DNS and time

OPNsense resolves `lan.buunk.org` and serves NTP (see the network docs). Fixed
addresses have host overrides such as `hgd1-hv01.lan.buunk.org`,
`s3.lan.buunk.org`, `k8s.lan.buunk.org`, `mon.lan.buunk.org`,
`api.lan.buunk.org` and `lab.buunk.org` (internal for now). Hosts also keep each other in
`/etc/hosts`, so they resolve each other when the router is down. Ceph needs
synced clocks, so hosts run chrony and prefer OPNsense.

## Configuration

| What | Where |
| --- | --- |
| Host NIC, VLANs, bridges, DNS servers, `/etc/hosts` | `modules/network.nix` |
| VM NICs on the bridges | `modules/microvm/host/networking.nix` |
| Addresses | `inventory.nix` → `vlans`, `hosts`, `vms` |

A new address in the inventory usually needs a DNS override on the router
too (network docs, [Router and switch](https://jurrebuunk.github.io/hgd1-network/operate/router-and-switch/)).

## Troubleshooting

- **Can't reach anything:** see [Troubleshooting → No access](../operate/troubleshooting.md#no-access).
- **A host lost its network after a change:** use the console or the
  previous boot generation; see [Roll back](../how-to/roll-back.md).

## Related

- [Remote access](remote-access.md) · [Addresses](../reference/addresses.md) · [Firewall](../reference/firewall.md)
