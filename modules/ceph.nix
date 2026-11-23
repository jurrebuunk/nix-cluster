# Ceph on every host: mon + mgr + one HDD OSD + an RGW (S3) gateway, all on the
# storage VLAN (br-stor, see modules/network.nix).
# Daemons only start once their keyring exists, so this can be deployed before
# scripts/ceph-bootstrap.sh has created the cluster. See CEPH.md.
{
  config,
  lib,
  pkgs,
  inventory,
  ...
}:
let
  hostName = config.networking.hostName;
  host = inventory.hosts.${hostName};
  rgwId = "rgw.${hostName}";
  monAddr = h: "[v2:${h.ip.storage}:3300,v1:${h.ip.storage}:6789]";
in
{
  services.ceph = {
    enable = true;

    global = {
      inherit (inventory.ceph) fsid;
      monInitialMembers = lib.concatStringsSep "," (lib.attrNames inventory.hosts);
      monHost = lib.concatStringsSep " " (map monAddr (lib.attrValues inventory.hosts));
      publicNetwork = inventory.vlans.storage.subnet;
    };

    # Pool/CRUSH defaults are read by the monitors, not just the OSDs.
    extraConfig = {
      # Never select the floating S3 VIP as a daemon's advertised address.
      "public addr" = host.ip.storage;
      "osd pool default size" = "3";
      "osd pool default min size" = "2";
      "osd crush chooseleaf type" = "1";
    };

    mon = {
      enable = true;
      daemons = [ hostName ];
    };

    mgr = {
      enable = true;
      daemons = [ hostName ];
    };

    osd = {
      enable = true;
      daemons = [ host.osd.id ];
      extraConfig = {
        # 16 GiB nodes also run VMs; keep each OSD around 2 GiB.
        "osd memory target" = toString (2 * 1024 * 1024 * 1024);
      };
    };

    rgw = {
      enable = true;
      daemons = [ rgwId ];
    };

    client = {
      enable = true;
      extraConfig."client.${rgwId}"."rgw frontends" = "beast endpoint=${host.ip.storage}:7480";
    };
  };

  environment.systemPackages = with pkgs; [
    ceph
    lvm2
    smartmontools
    jq
  ];

  # Ceph is only reachable on the storage VLAN (hosts and k3s VMs).
  networking.firewall.interfaces.br-stor = {
    allowedTCPPorts = [
      3300 # mon (msgr2)
      6789 # mon (msgr1)
      7480 # rgw / S3
      9283 # mgr prometheus module
    ];
    allowedTCPPortRanges = [
      {
        from = 6800;
        to = 7300;
      } # osd / mgr / mds
    ];
  };
}
