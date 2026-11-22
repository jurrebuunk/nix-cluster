# Fully declarative guests; only explicit VM restarts pick up a changed runner.
{
  config,
  lib,
  inventory,
  guestConfigurations,
  ...
}:
let
  # Select the guests assigned to this host.
  name = config.networking.hostName;
  host = inventory.hosts.${name};

  all = builtins.attrValues inventory.vms;
  enabled = lib.filterAttrs (_: vm: vm.enabled && vm.host == name) inventory.vms;
  netFor = (import ./vm-lib.nix { inherit lib; }).networkFor;

  # Collect identities and resource totals for inventory validation.
  identities = map (vm: vm.id) all;
  k8sIPs = map (vm: vm.ip.k8s) all;
  storageIPs = map (vm: vm.ip.storage) all;
  hostStorageIPs = map (h: h.ip.storage) (builtins.attrValues inventory.hosts);
  memory = lib.foldl' (sum: vm: sum + vm.memMB) 0 (builtins.attrValues enabled);

  # Attach each guest's two TAP interfaces to their respective bridges.
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
  # Fail at evaluation time rather than deploying invalid guest definitions.
  assertions = [
    {
      assertion = lib.all (vm: builtins.hasAttr vm.host inventory.hosts) all;
      message = "Every VM must refer to a host in inventory.hosts";
    }
    {
      assertion =
        lib.all (vm: vm.id > 0 && vm.id < 256) all && lib.length (lib.unique identities) == lib.length all;
      message = "VM ids must be unique integers in 1..255 (MAC/TAP identity)";
    }
    {
      assertion =
        lib.length (lib.unique k8sIPs) == lib.length all
        &&
          lib.length (lib.unique (storageIPs ++ hostStorageIPs)) == lib.length all + lib.length hostStorageIPs
        && lib.all (
          vm:
          lib.hasPrefix "10.10.40." vm.ip.k8s
          && lib.hasPrefix "10.10.30." vm.ip.storage
          && vm.ip.k8s != inventory.vlans.k8s.gateway
        ) all;
      message = "VM IPs must be unique, use VLAN 40/30 and not collide with host storage or the gateway";
    }
    {
      assertion = lib.all (
        vm:
        lib.elem vm.role [
          "server"
          "agent"
        ]
        && vm.memMB > 0
        && vm.vcpu > 0
        && vm.diskGB > 0
      ) all;
      message = "VM roles/resources must be valid and positive";
    }
    {
      assertion = enabled == { } || host.kvmAvailable;
      message = "${name}: KVM unavailable; enable VT-x in BIOS before enabling guests";
    }
    {
      assertion = memory <= 11264;
      message = "${name}: reserve at least ~4 GiB for the host/Ceph; guest RAM exceeds 11 GiB";
    }
  ];

  # Loading KVM is safe without a reboot where firmware exposes it. hv02's
  # firmware currently hides VMX, so do not create a failed modules-load unit.
  boot.kernelModules = lib.optionals host.kvmAvailable [ "kvm_intel" ];
  hardware.ksm.enable = false;

  # We use root-managed TAPs, not qemu-bridge-helper. Never allow its default
  # wildcard bridge ACL to expose management bridges to an unprivileged VMM.
  environment.etc."qemu/bridge.conf".text = "deny all\n";

  # Install updated runners without restarting an already-running guest.
  microvm = {
    stateDir = "/var/lib/microvms";
    vms = lib.mapAttrs (vmName: _: {
      evaluatedConfig = guestConfigurations.${vmName};
      autostart = true;
      restartIfChanged = false;
    }) enabled;
  };

  systemd.network.networks = lib.mapAttrs' (n: v: lib.nameValuePair "40-${n}" v) (
    builtins.listToAttrs tapNetworks
  );

  # The host must not route around OPNsense or expose local management on its
  # unnumbered K8S bridge (Linux otherwise has a weak-host IP model).
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

  # Wait for configured bridges before booting guests; don't wait for TAPs
  # themselves, since they are created by the VM service dependency.
  systemd.services = lib.mapAttrs' (
    vmName: _:
    lib.nameValuePair "microvm@${vmName}" {
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      unitConfig.ConditionPathExists = "/dev/kvm";
    }
  ) enabled;
}
