# clusterd's identity in Kubernetes: a ServiceAccount that may read nodes and
# pods, cordon and evict (a VM restart's drain), and hold its lock Lease in its
# own namespace. The token and CA go into secrets/clusterd-kubeconfig.age
# (docs/concepts/api.md#privileges).
{ lib, vm, ... }:
let
  namespace = "clusterd";
in
{
  services.k3s.manifests = lib.mkIf (vm.role == "server") {
    clusterd.content = [
      {
        apiVersion = "v1";
        kind = "Namespace";
        metadata.name = namespace;
      }
      {
        apiVersion = "v1";
        kind = "ServiceAccount";
        metadata = {
          name = "clusterd";
          inherit namespace;
        };
      }
      {
        apiVersion = "v1";
        kind = "Secret";
        type = "kubernetes.io/service-account-token";
        metadata = {
          name = "clusterd-token";
          inherit namespace;
          annotations."kubernetes.io/service-account.name" = "clusterd";
        };
      }
      {
        apiVersion = "rbac.authorization.k8s.io/v1";
        kind = "ClusterRole";
        metadata.name = "clusterd";
        rules = [
          {
            apiGroups = [ "" ];
            resources = [ "nodes" ];
            verbs = [ "get" "list" "patch" ];
          }
          {
            apiGroups = [ "" ];
            resources = [ "pods" ];
            verbs = [ "get" "list" ];
          }
          {
            apiGroups = [ "" ];
            resources = [ "pods/eviction" ];
            verbs = [ "create" ];
          }
        ];
      }
      {
        apiVersion = "rbac.authorization.k8s.io/v1";
        kind = "Role";
        metadata = {
          name = "clusterd-lock";
          inherit namespace;
        };
        rules = [
          {
            apiGroups = [ "coordination.k8s.io" ];
            resources = [ "leases" ];
            verbs = [ "get" "create" "update" "delete" ];
          }
        ];
      }
      {
        apiVersion = "rbac.authorization.k8s.io/v1";
        kind = "RoleBinding";
        metadata = {
          name = "clusterd-lock";
          inherit namespace;
        };
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "Role";
          name = "clusterd-lock";
        };
        subjects = [
          {
            kind = "ServiceAccount";
            name = "clusterd";
            inherit namespace;
          }
        ];
      }
      {
        apiVersion = "rbac.authorization.k8s.io/v1";
        kind = "ClusterRoleBinding";
        metadata.name = "clusterd";
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = "clusterd";
        };
        subjects = [
          {
            kind = "ServiceAccount";
            name = "clusterd";
            inherit namespace;
          }
        ];
      }
    ];
  };
}
