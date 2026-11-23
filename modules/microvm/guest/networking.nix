# Stable NIC identities, K8S gateway services and connected-only storage.
{ lib, inventory, vmName, vm, ... }:
let
  net = (import ../../../lib/vm-network.nix { inherit lib; }).networkFor vm;
  prefix = toString inventory.prefixLength;
in
{
  networking = {
    hostName = vmName;
    domain = inventory.site.domain;
    useDHCP = false;
    useNetworkd = true;
    nameservers = [ inventory.vlans.k8s.gateway ];
    search = [ inventory.site.domain ];
    timeServers = [ inventory.vlans.k8s.gateway ];
    firewall = {
      enable = true;
      interfaces.k8s.allowedTCPPorts = [ 22 ];
    };
  };

  # Match MACs, not probe order, so the K8S and storage NICs cannot swap.
  systemd.network = {
    enable = true;
    links = {
      "10-k8s" = {
        matchConfig.MACAddress = net.k8s.mac;
        linkConfig.Name = "k8s";
      };
      "10-storage" = {
        matchConfig.MACAddress = net.storage.mac;
        linkConfig.Name = "storage";
      };
    };
    networks = {
      "20-k8s" = {
        matchConfig.Name = "k8s";
        address = [ "${vm.ip.k8s}/${prefix}" ];
        gateway = [ inventory.vlans.k8s.gateway ];
        dns = [ inventory.vlans.k8s.gateway ];
        domains = [ inventory.site.domain ];
        networkConfig = {
          IPv6AcceptRA = false;
          LinkLocalAddressing = "no";
        };
      };
      "20-storage" = {
        matchConfig.Name = "storage";
        address = [ "${vm.ip.storage}/${prefix}" ];
        # No gateway, DNS or default route on storage.
        networkConfig = {
          IPv6AcceptRA = false;
          LinkLocalAddressing = "no";
        };
      };
    };
  };
}
