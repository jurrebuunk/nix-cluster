# Pure k3s facts shared by microVM host and guest modules.
{ inventory }:
{
  # Join address for servers and agents: the VIP itself, no DNS dependency.
  joinURL = "https://${inventory.k3s.apiVIP}:6443";
  apiURL = "https://${inventory.k3s.apiName}:6443";

  # Host directory with the tokens one VM role may read, shared read-only.
  hostSecretDir = role: "/run/k3s-secrets/${role}";
  guestSecretDir = "/run/k3s-secrets";
}
