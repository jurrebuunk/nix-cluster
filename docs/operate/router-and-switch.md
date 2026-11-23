---
icon: lucide/router
---

# Router and switch

OPNsense and the Aruba switch aren't managed by Nix. They're changed over SSH
or their web UIs, and backed up as files outside Git.

## Access

| Device | SSH | Web |
| --- | --- | --- |
| OPNsense `hgd1-fw01` | `ssh root@10.10.10.1` (key only) | `https://10.10.10.1` |
| Aruba `hgd1-sw01` | `ssh manager@10.10.10.2` (dedicated key) | – |

The switch's old SSH needs legacy algorithms; a matching `ssh_config` lives in
`~/.local/state/nix-cluster/network-rollout/`:

```sh
ssh -F ~/.local/state/nix-cluster/network-rollout/ssh_config hgd1-sw01
```

Both are reachable only from the site or through WARP. Without WARP: switch
port 1 or the OPNsense console.

## Back up

Before **every** change, export both configurations to
`~/.local/state/nix-cluster/network-rollout/`, with a UTC timestamp in the
name and mode 0600:

```sh
B=~/.local/state/nix-cluster/network-rollout
TS=$(date -u +%Y%m%dT%H%M%SZ)
ssh root@10.10.10.1 'cat /conf/config.xml' > "$B/opnsense-$TS.xml" && chmod 600 "$B/opnsense-$TS.xml"
```

For the switch, save `show running-config` the same way. These files contain
password hashes and keys: **never** commit them.

## Update OPNsense

1. Back up.
2. System → Firmware → Updates. OPNsense snapshots a boot environment before
   upgrading.
3. During the reboot the site loses internet and inter-VLAN routing. Ceph
   (storage VLAN, layer 2) keeps working.
4. Check DNS, NTP and remote access afterwards.

Installed: OPNsense 26.7.9_3 with `os-isc-dhcp` and `os-firewall-legacy`.

## Reboot the switch

A switch reboot interrupts **everything**, including Ceph traffic between the
hosts. Plan it like a site outage: save first (`write memory`), and expect
Ceph to report slow or blocked requests until it's back.

Firmware is still `YA.16.02.0012`; an update is on the to-do list.

## Monitoring

Both devices are part of [monitoring](../concepts/monitoring.md):

- **OPNsense:** plugin `os-node_exporter`, listening on `10.10.10.1:9100`
  (Services → Node Exporter), and a remote syslog destination to
  `10.10.20.10:514` UDP (System → Settings → Logging → Remote).
- **Aruba:** `snmp-server community "<community>" operator restricted` (read-only;
  the value is in `secrets/snmp-community.age`) and `logging 10.10.20.10` with
  `logging severity info`.

## Change DNS

Host overrides live in Services → Unbound DNS → Overrides. Keep them in line
with `inventory.nix`. TTL 60 for floating addresses (`s3`, `k8s`, `mon`, `api`).

## Related

- [Network](../concepts/network.md) · [Firewall](../reference/firewall.md)
- [Rebuild the network](rebuild-network.md)
