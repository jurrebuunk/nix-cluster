# Ceph facts for ceph-csi (installed from the workloads repo): kernel clients
# on every node, and the cluster's fsid and monitors as a ConfigMap.
{ lib, inventory, vm, ... }:
{
  boot.kernelModules = [
    "rbd"
    "ceph"
  ];

  services.k3s.manifests = lib.mkIf (vm.role == "server") {
    hgd1-ceph.content = {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = {
        name = "hgd1-ceph";
        namespace = "kube-system";
      };
      data = {
        fsid = inventory.ceph.fsid;
        monitors = lib.concatMapStringsSep "," (h: "${h.ip.storage}:6789") (
          lib.attrValues inventory.hosts
        );
        s3Endpoint = "https://${inventory.ceph.s3.hostname}";
      };
    };
  };
}
