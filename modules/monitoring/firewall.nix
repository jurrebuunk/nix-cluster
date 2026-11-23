# Query, ingest and syslog ports on the management NIC; log ingest from VMs on
# the storage bridge; VRRP only from the exact peers.
{ config, lib, inventory, ... }:
let
  host = inventory.hosts.${config.networking.hostName};
  nic = host.interface;
  peers = lib.filter (ip: ip != host.ip.infra) (map (h: h.ip.infra) (lib.attrValues inventory.hosts));
  vrrpRules = lib.concatMapStringsSep "\n" (peer: ''
    iptables -C nixos-fw -i ${nic} -s ${peer} -d ${host.ip.infra} -p vrrp -m ttl --ttl-eq 255 -j ACCEPT 2>/dev/null || \
      iptables -A nixos-fw -i ${nic} -s ${peer} -d ${host.ip.infra} -p vrrp -m ttl --ttl-eq 255 -j ACCEPT
  '') peers;
  removeVrrpRules = lib.concatMapStringsSep "\n" (peer: ''
    iptables -D nixos-fw -i ${nic} -s ${peer} -d ${host.ip.infra} -p vrrp -m ttl --ttl-eq 255 -j ACCEPT 2>/dev/null || true
  '') peers;
in
{
  networking.firewall = {
    interfaces.${nic} = {
      allowedTCPPorts = [
        8428 # VictoriaMetrics: queries and remote write from peers
        9428 # VictoriaLogs: queries and ingest from peers
        514 # syslog (router, switch)
      ];
      allowedUDPPorts = [ 514 ];
    };
    # Log ingest from the VMs' storage NICs.
    interfaces.br-stor.allowedTCPPorts = [ 9428 ];
    extraCommands = vrrpRules;
    extraStopCommands = removeVrrpRules;
  };
}
