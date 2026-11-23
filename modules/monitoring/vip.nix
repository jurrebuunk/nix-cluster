# Query address for Grafana and the browser: follows a host whose
# VictoriaMetrics and VictoriaLogs both answer.
{ config, lib, pkgs, inventory, ... }:
let
  cfg = inventory.monitoring;
  hostName = config.networking.hostName;
  host = inventory.hosts.${hostName};
  peers = lib.filter (ip: ip != host.ip.infra) (map (h: h.ip.infra) (lib.attrValues inventory.hosts));

  checkStores = pkgs.writeShellScript "check-monitoring" ''
    ${pkgs.curl}/bin/curl --silent --fail --max-time 1 --noproxy '*' http://127.0.0.1:8428/health >/dev/null &&
      ${pkgs.curl}/bin/curl --silent --fail --max-time 1 --noproxy '*' http://127.0.0.1:9428/health >/dev/null
  '';
in
{
  users.groups.keepalived_script = { };
  users.users.keepalived_script = {
    isSystemUser = true;
    group = "keepalived_script";
  };

  services.keepalived = {
    enable = true;
    enableScriptSecurity = true;
    openFirewall = false;
    vrrpScripts.monitoring = {
      script = "${checkStores}";
      user = "keepalived_script";
      interval = 2;
      timeout = 2;
      fall = 2;
      rise = 2;
      weight = 0;
    };
    vrrpInstances.monitoring = {
      interface = host.interface;
      state = "BACKUP";
      virtualRouterId = cfg.virtualRouterId;
      priority = 150 - 10 * lib.lists.findFirstIndex (name: name == hostName) 0 (lib.attrNames inventory.hosts);
      noPreempt = true;
      unicastSrcIp = host.ip.infra;
      unicastPeers = peers;
      virtualIps = [
        {
          addr = "${cfg.virtualIP}/32";
          dev = host.interface;
          label = "${host.interface}:mon";
        }
      ];
      trackScripts = [ "monitoring" ];
      extraConfig = ''
        version 3
        advert_int 1
        check_unicast_src
        unicast_fault_no_peer
        garp_master_delay 0
        garp_master_repeat 3
      '';
    };
  };
}
