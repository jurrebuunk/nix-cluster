# Query, ingest and syslog ports on the management NIC; ingest from VMs (and
# pods on them) on the storage bridge; VRRP only from the exact peers.
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
    # Ingest from the VMs' storage NICs: their own logs, and the metrics and
    # pod logs the k3s cluster's vmagent and Vector send (no router involved).
    interfaces.br-stor.allowedTCPPorts = [
      8428
      9428
    ];
    extraCommands = vrrpRules;
    extraStopCommands = removeVrrpRules;
  };
}
