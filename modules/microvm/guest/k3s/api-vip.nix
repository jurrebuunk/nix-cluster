# API VIP follows a server whose local apiserver answers; agents never hold it.
{ lib, pkgs, inventory, vmName, vm, ... }:
let
  cfg = inventory.k3s;
  servers = lib.filterAttrs (_: v: v.role == "server") inventory.vms;
  peers = map (v: v.ip.k8s) (lib.attrValues (removeAttrs servers [ vmName ]));

  # Any HTTP answer means the apiserver serves TLS; anonymous requests get 401.
  checkApi = pkgs.writeShellScript "check-k3s-api" ''
    code=$(${pkgs.curl}/bin/curl --silent --insecure --max-time 1 --noproxy '*' \
      --output /dev/null --write-out '%{http_code}' https://127.0.0.1:6443/livez)
    [ "$code" = 200 ] || [ "$code" = 401 ]
  '';
in
lib.mkIf (vm.role == "server") {
  users.groups.keepalived_script = { };
  users.users.keepalived_script = {
    isSystemUser = true;
    group = "keepalived_script";
  };

  services.keepalived = {
    enable = true;
    enableScriptSecurity = true;
    # firewall.nix owns the narrow rules, not the module's broad VRRP/AH opening.
    openFirewall = false;
    vrrpScripts.k3s_api = {
      script = "${checkApi}";
      user = "keepalived_script";
      interval = 2;
      timeout = 2;
      fall = 2;
      rise = 2;
      weight = 0;
    };
    vrrpInstances.k3s_api = {
      interface = "k8s";
      state = "BACKUP";
      virtualRouterId = cfg.virtualRouterId;
      priority = 150 - 10 * lib.lists.findFirstIndex (name: name == vmName) 0 (lib.attrNames servers);
      noPreempt = true;
      unicastSrcIp = vm.ip.k8s;
      unicastPeers = peers;
      virtualIps = [
        {
          addr = "${cfg.apiVIP}/32";
          dev = "k8s";
          label = "k8s:api";
        }
      ];
      trackScripts = [ "k3s_api" ];
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

  systemd.services.keepalived = {
    after = [ "k3s.service" ];
    wants = [ "k3s.service" ];
  };
}
