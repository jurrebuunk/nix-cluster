---
icon: lucide/router
---

# Router and switch

!!! repo "Lives in its own repo: hgd1-network"

    This page covers **the router and switch** on the hgd1 cluster: how it fits in and how I
    use it here. Code, development, releases and the full documentation are in
    the repo (private).

    [:fontawesome-brands-github: jurrebuunk/hgd1-network](https://github.com/jurrebuunk/hgd1-network){ .md-button .md-button--primary }

What runs on OPNsense and the Aruba switch, and how to reach them. **Changing
them is not done from this repo**: their configuration is Ansible in the
private [`hgd1-network`](https://github.com/jurrebuunk/hgd1-network) repo, which
also takes the backups. This page is for understanding and for emergencies.

!!! info "At a glance"

    **Router** OPNsense 26.7.9_3, `hgd1-fw01` · **Switch** HP/Aruba 2530-48G,
    `hgd1-sw01`, firmware `YA.16.02.0012` · **Managed in**
    [`hgd1-network`](https://github.com/jurrebuunk/hgd1-network) (Ansible) ·
    **Design** [Network](../concepts/network.md), [Firewall](../reference/firewall.md)

## Access

| Device | SSH | Web |
| --- | --- | --- |
| OPNsense `hgd1-fw01` | `ssh root@10.10.10.1` (key only) | `https://10.10.10.1` |
| Aruba `hgd1-sw01` | `ssh manager@10.10.10.2` (dedicated key, legacy algorithms) | – |

Both are reachable only from the site or through WARP. Without WARP: switch
port 1 or the OPNsense console. Use direct access to look, or in an
emergency; make lasting changes in `hgd1-network`, or its next run overwrites
them.

## What's configured

| Device | Configuration |
| --- | --- |
| OPNsense | VLAN interfaces 20/40/100, DHCP on mgmt and users, outbound NAT, Unbound with DNSSEC and the host overrides, NTP, the inter-VLAN firewall policy and remote-access aliases, the Sunshine forwards, plugins `os-isc-dhcp`, `os-firewall-legacy` and `os-node_exporter`, syslog to `10.10.20.10` |
| Aruba | VLANs 10/20/30/40/100/999, port roles, management on `10.10.10.2`, SNTP from OPNsense, key-only SSH, read-only SNMP, syslog to `10.10.20.10` |

The why behind each part is in [Network](../concepts/network.md) and
[Firewall](../reference/firewall.md); how they feed monitoring is in
[Monitoring](../concepts/monitoring.md).

## Changes

Everything below happens in [`hgd1-network`](https://github.com/jurrebuunk/hgd1-network):

| Task | In `hgd1-network` |
| --- | --- |
| DNS host override (new VM, new VIP) | Unbound overrides in its variables; keep them in line with `inventory.nix` |
| Firewall rule or alias | Firewall variables; follow the [policy](../reference/firewall.md) |
| Switch port role | Switch variables |
| Backups | Taken before every run |
| Firmware updates | Its runbook for OPNsense and the Aruba |

## Reboot impact

- **OPNsense:** the site loses internet, inter-VLAN routing, DNS and remote
  access. Ceph (storage VLAN, layer 2) keeps working.
- **Switch:** interrupts **everything**, including Ceph traffic between the
  hosts. Plan it like a site outage; expect Ceph to report slow or blocked
  requests until it's back.

## Related

- [Network](../concepts/network.md) · [Firewall](../reference/firewall.md) ·
  [Rebuild the network](rebuild-network.md) ·
  [Repositories](../reference/repositories.md)
