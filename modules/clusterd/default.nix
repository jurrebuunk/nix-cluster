# Platform API on every host. The program and its NixOS module come from the
# clusterd flake input; this configures it from the inventory.
{ config, lib, inventory, ... }:
let
  cfg = inventory.api;
  hostName = config.networking.hostName;
  host = inventory.hosts.${hostName};
  store = name: h: port: if name == hostName then "http://127.0.0.1:${toString port}" else "http://${h.ip.infra}:${toString port}";
in
{
  imports = [
    ./tls.nix
    ./vip.nix
    ./firewall.nix
  ];

  assertions = [
    {
      assertion =
        lib.hasPrefix "10.10.20." cfg.virtualIP
        && !lib.elem cfg.virtualIP (
          map (h: h.ip.infra) (lib.attrValues inventory.hosts)
          ++ [ inventory.monitoring.virtualIP inventory.vlans.infra.gateway ]
          ++ lib.attrValues inventory.monitoring.pingTargets
        );
      message = "API VIP must be a free address on the infra VLAN";
    }
    {
      assertion = cfg.virtualRouterId != inventory.monitoring.virtualRouterId;
      message = "API and monitoring VIPs share the infra VLAN; they need different VRRP ids";
    }
  ];

  age.secrets = {
    api-tokens.file = ../../secrets/api-tokens.age;
    clusterd-kubeconfig.file = ../../secrets/clusterd-kubeconfig.age;
    clusterd-ceph-keyring.file = ../../secrets/clusterd-ceph-keyring.age;
    clusterd-s3-admin.file = ../../secrets/clusterd-s3-admin.age;
  };

  services.clusterd = {
    enable = true;
    tokensFile = config.age.secrets.api-tokens.path;
    kubeconfigFile = config.age.secrets.clusterd-kubeconfig.path;
    ceph.keyringFile = config.age.secrets.clusterd-ceph-keyring.path;
    # VM restarts: polkit lets the clusterd user restart/start/stop only these.
    manageUnitPrefixes = [ "microvm@" ];
    # Bucket usage through the RGW admin API (read-only user `clusterd`).
    s3.credentialsFile = config.age.secrets.clusterd-s3-admin.path;
    settings = {
      site = inventory.site.name;
      host = hostName;
      # Own address for peers and the health check, plus the VIP (bound ahead
      # of time thanks to ip_nonlocal_bind).
      listen = [
        "${host.ip.infra}:443"
        "${cfg.virtualIP}:443"
      ];
      metrics_listen = "127.0.0.1:9180";
      server_name = cfg.hostname;
      tls = {
        cert = "/var/lib/acme/${cfg.hostname}/fullchain.pem";
        key = "/var/lib/acme/${cfg.hostname}/key.pem";
      };
      hosts = lib.mapAttrsToList (name: h: {
        inherit name;
        api = "https://${h.ip.infra}";
        metrics = store name h 8428;
        logs = store name h 9428;
        rgw = "http://${h.ip.storage}:7480";
      }) inventory.hosts;
      s3 = {
        endpoint = "https://${inventory.ceph.s3.hostname}";
        data_pool = "default.rgw.buckets.data";
      };
      vips = [
        { name = "api"; address = cfg.virtualIP; }
        { name = "monitoring"; address = inventory.monitoring.virtualIP; }
      ]
      ++ lib.optional inventory.ceph.s3.enable { name = "s3"; address = inventory.ceph.s3.virtualIP; };
      vms = lib.mapAttrsToList (name: vm: {
        inherit name;
        inherit (vm) host enabled;
      }) inventory.vms;
    };
  };

  systemd.services.clusterd = {
    # A missing certificate would fail the start; wait for the first issuance.
    requires = [ "acme-${cfg.hostname}.service" ];
    after = [ "acme-${cfg.hostname}.service" ];
    # Secrets are systemd credentials, copied in at start: a changed secret
    # (a new token, say) needs a restart, which the deploy then does.
    restartTriggers = map (s: config.age.secrets.${s}.file) [
      "api-tokens"
      "clusterd-kubeconfig"
      "clusterd-ceph-keyring"
      "clusterd-s3-admin"
    ];
  };
}
