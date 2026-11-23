# Private S3 HA endpoint, independent of k3s. Children own their enable guards.
{ lib, inventory, ... }:
let
  cfg = inventory.ceph.s3;
  hosts = lib.attrValues inventory.hosts;
  assignedStorageIPs =
    map (host: host.ip.storage) hosts ++ map (vm: vm.ip.storage) (lib.attrValues inventory.vms);
in
{
  imports = [
    ./tls.nix
    ./proxy.nix
    ./failover.nix
    ./firewall.nix
  ];

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.length hosts >= 2 && !lib.elem cfg.virtualIP assignedStorageIPs;
        message = "S3 HA needs multiple hosts and a VIP distinct from all host/guest storage addresses";
      }
      {
        assertion =
          lib.hasPrefix "10.10.30." cfg.virtualIP
          && !lib.elem cfg.virtualIP [
            "10.10.30.0"
            "10.10.30.255"
          ];
        message = "S3 VIP must be a usable address on the unrouted storage VLAN";
      }
    ];
  };
}
