# k3s ports on the K8S NIC only; unicast VRRP restricted to exact server peers.
{ lib, inventory, vmName, vm, ... }:
let
  isServer = vm.role == "server";
  servers = lib.filterAttrs (_: v: v.role == "server") inventory.vms;
  peers = map (v: v.ip.k8s) (lib.attrValues (removeAttrs servers [ vmName ]));
  vrrpRules = lib.concatMapStringsSep "\n" (peer: ''
    iptables -C nixos-fw -i k8s -s ${peer} -d ${vm.ip.k8s} -p vrrp -m ttl --ttl-eq 255 -j ACCEPT 2>/dev/null || \
      iptables -A nixos-fw -i k8s -s ${peer} -d ${vm.ip.k8s} -p vrrp -m ttl --ttl-eq 255 -j ACCEPT
  '') peers;
  removeVrrpRules = lib.concatMapStringsSep "\n" (peer: ''
    iptables -D nixos-fw -i k8s -s ${peer} -d ${vm.ip.k8s} -p vrrp -m ttl --ttl-eq 255 -j ACCEPT 2>/dev/null || true
  '') peers;
in
{
  networking.firewall = {
    interfaces.k8s = {
      # kubelet; servers add the API and etcd peer/client ports.
      allowedTCPPorts = [
        10250
      ]
      ++ lib.optionals isServer [
        6443
        2379
        2380
      ];
      # flannel VXLAN
      allowedUDPPorts = [ 8472 ];
    };
    # Pod and overlay traffic is policed by Kubernetes, not the host firewall.
    trustedInterfaces = [
      "cni0"
      "flannel.1"
    ];
    extraCommands = lib.optionalString isServer vrrpRules;
    extraStopCommands = lib.optionalString isServer removeVrrpRules;
  };
}
