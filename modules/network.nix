# Host networking on one NIC (docs/concepts/network.md):
#   enp2s0 (untagged, VLAN 20)  host management, default route
#   enp2s0.30 -> br-stor        Ceph, host address, not routed
#   enp2s0.40 -> br-k8s         k3s VMs later, no host address
{ config, lib, inventory, ... }:
let
  inherit (inventory) vlans prefixLength;
  host = inventory.hosts.${config.networking.hostName};
  nic = host.interface;
  vlanIf = name: "${nic}.${toString vlans.${name}.id}";
in
{
  networking.useDHCP = false;
  networking.useNetworkd = true;
  networking.domain = inventory.site.domain;
  networking.search = [ inventory.site.domain ];
  networking.nameservers = inventory.dns;
  networking.firewall.interfaces.${nic}.allowedTCPPorts = [ 22 ];

  # Peers resolve each other without depending on OPNsense DNS.
  networking.hosts = lib.mapAttrs' (
    name: h: lib.nameValuePair h.ip.infra [ "${name}.${inventory.site.domain}" name ]
  ) inventory.hosts;

  # Only announce .local names on the management network.
  services.avahi.allowInterfaces = [ nic ];

  systemd.network = {
    enable = true;

    netdevs = {
      "20-${vlanIf "storage"}" = {
        netdevConfig = { Kind = "vlan"; Name = vlanIf "storage"; };
        vlanConfig.Id = vlans.storage.id;
      };
      "20-${vlanIf "k8s"}" = {
        netdevConfig = { Kind = "vlan"; Name = vlanIf "k8s"; };
        vlanConfig.Id = vlans.k8s.id;
      };
      "30-br-stor".netdevConfig = { Kind = "bridge"; Name = "br-stor"; };
      "30-br-k8s".netdevConfig = { Kind = "bridge"; Name = "br-k8s"; };
    };

    networks = {
      "10-${nic}" = {
        matchConfig.Name = nic;
        address = [ "${host.ip.infra}/${toString prefixLength}" ];
        gateway = [ vlans.infra.gateway ];
        dns = inventory.dns;
        domains = [ inventory.site.domain ];
        vlan = [ (vlanIf "storage") (vlanIf "k8s") ];
        networkConfig.IPv6AcceptRA = false;
        linkConfig.RequiredForOnline = "routable";
      };

      "20-${vlanIf "storage"}" = {
        matchConfig.Name = vlanIf "storage";
        networkConfig.Bridge = "br-stor";
        linkConfig.RequiredForOnline = "enslaved";
      };
      "20-${vlanIf "k8s"}" = {
        matchConfig.Name = vlanIf "k8s";
        networkConfig.Bridge = "br-k8s";
        linkConfig.RequiredForOnline = "enslaved";
      };

      "30-br-stor" = {
        matchConfig.Name = "br-stor";
        address = [ "${host.ip.storage}/${toString prefixLength}" ];
        networkConfig = {
          IPv6AcceptRA = false;
          LinkLocalAddressing = "no";
        };
        linkConfig.RequiredForOnline = "routable";
      };
      "30-br-k8s" = {
        matchConfig.Name = "br-k8s";
        networkConfig = {
          IPv6AcceptRA = false;
          LinkLocalAddressing = "no";
          ConfigureWithoutCarrier = true;
        };
        linkConfig.RequiredForOnline = "no";
      };
    };
  };
}
