# Attach guest TAPs to their bridges and prevent host/router-policy bypasses.
{ config, lib, inventory, ... }:
let
  name = config.networking.hostName;
  enabled = lib.filterAttrs (_: vm: vm.enabled && vm.host == name) inventory.vms;
  netFor = (import ../../../lib/vm-network.nix { inherit lib; }).networkFor;
  tapNetworks = lib.concatMap (
    vm:
    let
      net = netFor vm;
    in
    [
      {
        name = net.k8s.tap;
        value = {
          matchConfig.Name = net.k8s.tap;
          networkConfig = {
            Bridge = "br-k8s";
            LinkLocalAddressing = "no";
            IPv6AcceptRA = false;
          };
          linkConfig.RequiredForOnline = "no";
        };
      }
      {
        name = net.storage.tap;
        value = {
          matchConfig.Name = net.storage.tap;
          networkConfig = {
            Bridge = "br-stor";
            LinkLocalAddressing = "no";
            IPv6AcceptRA = false;
          };
          linkConfig.RequiredForOnline = "no";
        };
      }
    ]
  ) (builtins.attrValues enabled);
in
{
  systemd.network.networks = lib.mapAttrs' (n: v: lib.nameValuePair "40-${n}" v) (
    builtins.listToAttrs tapNetworks
  );

  # Linux's weak-host model must not expose management on unnumbered br-k8s.
  # Permit normal L2 bridge traffic, but block routing around OPNsense.
  networking.firewall.extraCommands = ''
    for family in iptables ip6tables; do
      $family -C INPUT -i br-k8s -j DROP 2>/dev/null || $family -I INPUT 1 -i br-k8s -j DROP
      for bridge in br-k8s br-stor; do
        $family -C FORWARD -i "$bridge" ! -o "$bridge" -j DROP 2>/dev/null || \
          $family -I FORWARD 1 -i "$bridge" ! -o "$bridge" -j DROP
        $family -C FORWARD -o "$bridge" ! -i "$bridge" -j DROP 2>/dev/null || \
          $family -I FORWARD 1 -o "$bridge" ! -i "$bridge" -j DROP
      done
    done
  '';

  networking.firewall.extraStopCommands = ''
    for family in iptables ip6tables; do
      $family -D INPUT -i br-k8s -j DROP 2>/dev/null || true
      for bridge in br-k8s br-stor; do
        $family -D FORWARD -i "$bridge" ! -o "$bridge" -j DROP 2>/dev/null || true
        $family -D FORWARD -o "$bridge" ! -i "$bridge" -j DROP 2>/dev/null || true
      done
    done
  '';
}
