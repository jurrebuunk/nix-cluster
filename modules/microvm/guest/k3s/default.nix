# k3s node: servers run embedded etcd behind the API VIP; agents join through
# it. All state lives on the persistent /var/lib volume.
{ lib, inventory, vmName, vm, ... }:
let
  cfg = inventory.k3s;
  k3s = import ../../../../lib/k3s.nix { inherit inventory; };
  isServer = vm.role == "server";
  bootstrap = vmName == cfg.bootstrapServer;
in
{
  imports = [
    ./api-vip.nix
    ./firewall.nix
    ./ceph.nix
    ./clusterd.nix
  ];

  boot.kernelModules = [
    "br_netfilter"
    "overlay"
  ];
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.bridge.bridge-nf-call-iptables" = 1;
    "net.bridge.bridge-nf-call-ip6tables" = 1;
  };

  services.k3s = {
    enable = true;
    role = vm.role;
    clusterInit = bootstrap;
    serverAddr = lib.optionalString (!bootstrap) k3s.joinURL;
    tokenFile = "${k3s.guestSecretDir}/${vm.role}-token";
    agentTokenFile = if isServer then "${k3s.guestSecretDir}/agent-token" else null;
    nodeIP = vm.ip.k8s;
    # Registration-time only: a moved VM is deleted and rejoins (docs/concepts/k3s.md).
    nodeLabel = [ "topology.kubernetes.io/zone=${vm.host}" ];
    # Ingress and load balancers come from the workloads repo.
    disable = lib.optionals isServer [
      "traefik"
      "servicelb"
    ];
    gracefulNodeShutdown.enable = true;
    # Root is tmpfs: keep container logs on the NVMe volume, not in RAM.
    extraKubeletConfig.podLogsDir = "/var/lib/kubelet-pod-logs";
    extraFlags = [
      "--flannel-iface=k8s"
    ]
    ++ lib.optionals isServer [
      "--tls-san=${cfg.apiName}"
      "--tls-san=${cfg.apiVIP}"
      # Quoted: systemd would split the cron expression into arguments.
      ''--etcd-snapshot-schedule-cron="0 */6 * * *"''
      "--etcd-snapshot-retention=20"
    ];
  };

  # The node password must survive reboots, or the servers reject the node.
  systemd.tmpfiles.rules = [
    "d /var/lib/rancher/node 0700 root root -"
    "L+ /etc/rancher/node - - - - /var/lib/rancher/node"
  ];

  systemd.services.k3s.unitConfig.RequiresMountsFor = [
    "/var/lib"
    k3s.guestSecretDir
  ];
}
