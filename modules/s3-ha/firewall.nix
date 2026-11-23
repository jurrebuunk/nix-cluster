# Storage-only HTTPS; unicast VRRP restricted to exact peers and TTL 255.
{ config, lib, inventory, ... }:
let
  cfg = inventory.ceph.s3;
  host = inventory.hosts.${config.networking.hostName};
  peers = lib.filter (ip: ip != host.ip.storage) (
    map (peer: peer.ip.storage) (lib.attrValues inventory.hosts)
  );
  vrrpRules = lib.concatMapStringsSep "\n" (peer: ''
    iptables -C nixos-fw -i br-stor -s ${peer} -d ${host.ip.storage} -p vrrp -m ttl --ttl-eq 255 -j ACCEPT 2>/dev/null || \
      iptables -A nixos-fw -i br-stor -s ${peer} -d ${host.ip.storage} -p vrrp -m ttl --ttl-eq 255 -j ACCEPT
  '') peers;
  removeVrrpRules = lib.concatMapStringsSep "\n" (peer: ''
    iptables -D nixos-fw -i br-stor -s ${peer} -d ${host.ip.storage} -p vrrp -m ttl --ttl-eq 255 -j ACCEPT 2>/dev/null || true
  '') peers;
in
lib.mkIf cfg.enable {
  # No management listener or router storage route is added.
  networking.firewall = {
    interfaces.br-stor.allowedTCPPorts = [ 443 ];
    extraCommands = vrrpRules;
    extraStopCommands = removeVrrpRules;
  };
}
