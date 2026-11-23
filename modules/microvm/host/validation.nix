# Reject invalid inventory identities, networking and resource allocations.
{ config, lib, inventory, ... }:
let
  name = config.networking.hostName;
  host = inventory.hosts.${name};
  all = builtins.attrValues inventory.vms;
  enabled = lib.filterAttrs (_: vm: vm.enabled && vm.host == name) inventory.vms;
  identities = map (vm: vm.id) all;
  k8sIPs = map (vm: vm.ip.k8s) all;
  storageIPs = map (vm: vm.ip.storage) all;
  hostStorageIPs = map (host: host.ip.storage) (builtins.attrValues inventory.hosts);
  memory = lib.foldl' (sum: vm: sum + vm.memMB) 0 (builtins.attrValues enabled);
in
{
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
      assertion =
        lib.hasPrefix "10.10.40." inventory.k3s.apiVIP
        && !lib.elem inventory.k3s.apiVIP (k8sIPs ++ [ inventory.vlans.k8s.gateway ]);
      message = "k3s API VIP must be a free address on VLAN 40";
    }
    {
      assertion =
        inventory.k3s.bootstrapServer == null
        || (inventory.vms.${inventory.k3s.bootstrapServer} or { role = null; }).role == "server";
      message = "k3s.bootstrapServer must be null or a server VM";
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
}
