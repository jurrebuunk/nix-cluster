# Exporters on this host and one vmagent that scrapes them, this host's VMs,
# the router and switch, and probes from here. It writes to every host's
# VictoriaMetrics and buffers on disk while a peer is down.
{ config, lib, pkgs, inventory, ... }:
let
  cfg = inventory.monitoring;
  hostName = config.networking.hostName;
  host = inventory.hosts.${hostName};
  myVMs = lib.filterAttrs (_: vm: vm.enabled && vm.host == hostName) inventory.vms;
  peers = lib.attrValues inventory.hosts;

  local = job: port: {
    job_name = job;
    static_configs = [
      {
        targets = [ "127.0.0.1:${toString port}" ];
        labels.instance = hostName;
      }
    ];
  };

  # Probes keep the vantage point: each host's view is its own series.
  probe = job: module: targets: {
    job_name = job;
    metrics_path = "/probe";
    params.module = [ module ];
    static_configs = lib.mapAttrsToList (name: target: {
      targets = [ target ];
      labels = {
        instance = name;
        probe_from = hostName;
      };
    }) targets;
    relabel_configs = [
      {
        source_labels = [ "__address__" ];
        target_label = "__param_target";
      }
      {
        target_label = "__address__";
        replacement = "127.0.0.1:9115";
      }
    ];
  };

  blackboxConfig = pkgs.writeText "blackbox.yml" (
    builtins.toJSON {
      modules = {
        icmp = {
          prober = "icmp";
          timeout = "5s";
          icmp.preferred_ip_protocol = "ip4";
        };
        dns_internal = {
          prober = "dns";
          timeout = "5s";
          dns = {
            query_name = "${lib.head (lib.attrNames inventory.hosts)}.${inventory.site.domain}";
            query_type = "A";
            valid_rcodes = [ "NOERROR" ];
            preferred_ip_protocol = "ip4";
          };
        };
        dns_external = {
          prober = "dns";
          timeout = "5s";
          dns = {
            query_name = "cache.nixos.org";
            query_type = "A";
            valid_rcodes = [ "NOERROR" ];
            preferred_ip_protocol = "ip4";
          };
        };
        # Anonymous S3 requests are refused with 403; TLS and expiry are what matter.
        https_s3 = {
          prober = "http";
          timeout = "5s";
          http = {
            valid_status_codes = [ 200 403 ];
            fail_if_not_ssl = true;
            preferred_ip_protocol = "ip4";
          };
        };
        https_2xx = {
          prober = "http";
          timeout = "10s";
          http = {
            fail_if_not_ssl = true;
            preferred_ip_protocol = "ip4";
          };
        };
        # k3s serves its own CA; check the handshake and certificate expiry.
        tls_k3s = {
          prober = "tcp";
          timeout = "5s";
          tcp = {
            tls = true;
            tls_config.insecure_skip_verify = true;
            preferred_ip_protocol = "ip4";
          };
        };
      };
    }
  );

  scrapeConfigs = lib.optional inventory.ceph.s3.enable (local "haproxy" 8405) ++ [
    (local "clusterd" 9180)
    (local "node" 9100)
    (local "smartctl" 9633)
    (local "cloudflared" 20241)
    (local "victoriametrics" 8428)
    (local "victorialogs" 9428)
    (local "vmagent" 8429)
    (local "vector" 9598)
    {
      # Only the active manager returns data; one instance label keeps the
      # series continuous when the active manager moves to another host.
      job_name = "ceph";
      honor_labels = true;
      static_configs = [
        {
          targets = [ "${host.ip.storage}:9283" ];
          labels.instance = "ceph";
        }
      ];
    }
    {
      job_name = "vm-node";
      static_configs = lib.mapAttrsToList (name: vm: {
        targets = [ "${vm.ip.storage}:9100" ];
        labels = {
          instance = name;
          hypervisor = vm.host;
        };
      }) myVMs;
    }
    {
      job_name = "router-node";
      static_configs = [
        {
          targets = [ "${cfg.router.ip}:9100" ];
          labels.instance = cfg.router.name;
        }
      ];
    }
    {
      job_name = "switch-snmp";
      metrics_path = "/snmp";
      params = {
        module = [
          "if_mib"
          "system"
        ];
        auth = [ "hgd1" ];
      };
      static_configs = [
        {
          targets = [ cfg.switch.ip ];
          labels.instance = cfg.switch.name;
        }
      ];
      relabel_configs = [
        {
          source_labels = [ "__address__" ];
          target_label = "__param_target";
        }
        {
          target_label = "__address__";
          replacement = "127.0.0.1:9116";
        }
      ];
    }
    (probe "probe-ping" "icmp" (
      {
        ${cfg.router.name} = cfg.router.ip;
        ${cfg.switch.name} = cfg.switch.ip;
        s3-vip = inventory.ceph.s3.virtualIP;
        k8s-vip = inventory.k3s.apiVIP;
        api-vip = inventory.api.virtualIP;
        internet = "1.1.1.1";
      }
      // cfg.pingTargets
      // lib.mapAttrs (_: h: h.ip.infra) (removeAttrs inventory.hosts [ hostName ])
    ))
    (probe "probe-dns" "dns_internal" { internal = inventory.vlans.infra.gateway; })
    (probe "probe-dns-external" "dns_external" { external = inventory.vlans.infra.gateway; })
    (probe "probe-s3" "https_s3" { s3 = "https://${inventory.ceph.s3.hostname}/"; })
    (probe "probe-api" "https_2xx" { api = "https://${inventory.api.hostname}/v1/health"; })
    (probe "probe-k8s-api" "tls_k3s" { k8s-api = "${inventory.k3s.apiVIP}:6443"; })
    (probe "probe-internet" "https_2xx" { nix-cache = "https://cache.nixos.org/nix-cache-info"; })
  ];
in
{
  services.prometheus.exporters = {
    node = {
      enable = true;
      listenAddress = "127.0.0.1";
      enabledCollectors = [ "systemd" ];
    };
    smartctl = {
      enable = true;
      listenAddress = "127.0.0.1";
    };
    blackbox = {
      enable = true;
      listenAddress = "127.0.0.1";
      configFile = blackboxConfig;
    };
    snmp = {
      enable = true;
      listenAddress = "127.0.0.1";
      # Upstream's generated modules (if_mib, system, ...); auth comes separately.
      configurationPath = pkgs.runCommand "snmp.yml" { } ''
        cp ${pkgs.prometheus-snmp-exporter.src}/snmp.yml $out
      '';
      # The community lives in an agenix auth file (snmp_exporter only expands
      # env vars for SNMPv3 credentials), passed in as a systemd credential.
      extraFlags = [ "--config.file=%d/snmp-auth" ];
    };
  };

  systemd.services.prometheus-snmp-exporter.serviceConfig.LoadCredential = [
    "snmp-auth:${config.age.secrets.snmp-community.path}"
  ];

  age.secrets.snmp-community.file = ../../secrets/snmp-community.age;

  services.vmagent = {
    enable = true;
    prometheusConfig = {
      global = {
        scrape_interval = "30s";
        scrape_timeout = "10s";
      };
      scrape_configs = scrapeConfigs;
    };
    extraArgs = [
      "-httpListenAddr=127.0.0.1:8429"
      "-remoteWrite.tmpDataPath=%C/vmagent/remote_write_tmp"
      "-remoteWrite.maxDiskUsagePerURL=1GB"
    ]
    ++ map (h: "-remoteWrite.url=http://${h.ip.infra}:8428/api/v1/write") peers;
  };
}
