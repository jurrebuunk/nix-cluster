# Metrics and logs for the infrastructure, independent of k3s and Ceph: every
# host collects, stores a full copy on its NVMe and answers queries.
{ lib, inventory, ... }:
let
  cfg = inventory.monitoring;
  infraIPs = map (h: h.ip.infra) (lib.attrValues inventory.hosts);
in
{
  imports = [
    ./storage.nix
    ./collection.nix
    ./logs.nix
    ./vip.nix
    ./firewall.nix
  ];

  assertions = [
    {
      assertion =
        lib.hasPrefix "10.10.20." cfg.virtualIP
        && !lib.elem cfg.virtualIP (
          infraIPs ++ lib.attrValues cfg.pingTargets ++ [ inventory.vlans.infra.gateway ]
        );
      message = "Monitoring VIP must be a free address on the infra VLAN";
    }
  ];
}
