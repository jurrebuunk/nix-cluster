# Single source of truth for cluster-wide facts. Nothing in here is secret.
# Network design: network/PLAN.md.
{
  site = {
    name = "hgd1";
    domain = "lan.buunk.org";
  };

  # Third octet = VLAN ID. Storage is not routed (no gateway).
  vlans = {
    mgmt = { id = 10; subnet = "10.10.10.0/24"; gateway = "10.10.10.1"; };
    infra = { id = 20; subnet = "10.10.20.0/24"; gateway = "10.10.20.1"; };
    storage = { id = 30; subnet = "10.10.30.0/24"; };
    k8s = { id = 40; subnet = "10.10.40.0/24"; gateway = "10.10.40.1"; };
    users = { id = 100; subnet = "10.10.100.0/24"; gateway = "10.10.100.1"; };
  };
  prefixLength = 24;

  # OPNsense on the infra VLAN.
  dns = [ "10.10.20.1" ];
  ntp = [ "10.10.20.1" ];

  ceph = {
    fsid = "fcc8817c-7074-4218-b9da-b940c2787c71";
    s3 = {
      enable = true;
      hostname = "s3.lan.buunk.org";
      virtualIP = "10.10.30.10";
      virtualRouterId = 30;
      acmeEmail = "jurrebuunk@outlook.com";
      # DNS-01 validated against staging before enabling production certificates.
      acmeServer = "https://acme-v02.api.letsencrypt.org/directory";
    };
  };

  # `ip.infra`: host management (untagged on the switch port).
  # `ip.storage`: Ceph (VLAN 30, tagged).
  # `mac`: onboard NIC, for reference.
  # `hostKey`: SSH host key, used by agenix (secrets/secrets.nix).
  # `hdd`: whole disk handed to Ceph; wiped by scripts/ceph-bootstrap.sh.
  hosts = {
    hgd1-hv01 = {
      ip = { infra = "10.10.20.11"; storage = "10.10.30.11"; };
      interface = "enp2s0";
      mac = "fc:3f:db:10:c6:c9";
      kvmAvailable = true;
      hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOqb7IBsWiLLDnzULaYlSL+B/znTun+871vI8hyRMeRn";
      hdd = "/dev/disk/by-id/ata-HGST_HTS721010A9E630_JR1004BNK14S5M";
      osd = { id = "0"; uuid = "6dccaa87-db1f-4c5d-b0a3-ec7edfaa2c55"; };
    };
    hgd1-hv02 = {
      ip = { infra = "10.10.20.12"; storage = "10.10.30.12"; };
      interface = "enp2s0";
      mac = "fc:3f:db:0a:b1:c3";
      # CPU supports VT-x, but firmware currently hides VMX and /dev/kvm.
      # Enable virtualization in BIOS after the HDD test, then update this flag.
      kvmAvailable = false;
      hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOWM/JrVeGLdoY8URpx5bu4w03HjVZKtF2PX4zR+l3IW";
      hdd = "/dev/disk/by-id/ata-HGST_HTS721010A9E630_JR1000D30JXXWF";
      osd = { id = "1"; uuid = "bdb491cd-e5a9-42b7-8118-5abdb0cd0f33"; };
    };
    hgd1-hv03 = {
      ip = { infra = "10.10.20.13"; storage = "10.10.30.13"; };
      interface = "enp2s0";
      mac = "fc:3f:db:0a:c1:42";
      kvmAvailable = true;
      hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAUY77uRABdXlI6dWbgSKfmTyaVJ+F/lv/s4qOGoN3Cc";
      hdd = "/dev/disk/by-id/ata-HGST_HTS721010A9E630_JR1000D30JXYRF";
      osd = { id = "2"; uuid = "209dd80f-6c69-4cf4-bcf3-622337279486"; };
    };
  };

  # VM resources live on host NVMe, not the reserved Ceph HDDs. Only m01 is
  # enabled in step 3 to prove the platform; deploying k3s/all five is step 4.
  # id determines stable, unique TAP names and MAC addresses (see lib/vm-network.nix).
  vms = {
    hgd1-k8m01 = {
      host = "hgd1-hv01"; enabled = true; id = 11; role = "server";
      # Verified from the trusted hypervisor console; private key is on var-lib.img.
      hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF0QRgl9LwkEUSkSxh/MY5wlrIqLS299vkPkc+YVzq1D";
      vcpu = 2; memMB = 4096; diskGB = 60;
      ip = { k8s = "10.10.40.11"; storage = "10.10.30.21"; };
    };
    hgd1-k8m02 = {
      host = "hgd1-hv02"; enabled = false; id = 12; role = "server";
      vcpu = 2; memMB = 4096; diskGB = 60;
      ip = { k8s = "10.10.40.12"; storage = "10.10.30.22"; };
    };
    hgd1-k8m03 = {
      host = "hgd1-hv03"; enabled = false; id = 13; role = "server";
      vcpu = 2; memMB = 4096; diskGB = 60;
      ip = { k8s = "10.10.40.13"; storage = "10.10.30.23"; };
    };
    hgd1-k8w01 = {
      host = "hgd1-hv01"; enabled = false; id = 21; role = "agent";
      vcpu = 4; memMB = 4096; diskGB = 60;
      ip = { k8s = "10.10.40.21"; storage = "10.10.30.31"; };
    };
    hgd1-k8w02 = {
      host = "hgd1-hv02"; enabled = false; id = 22; role = "agent";
      vcpu = 4; memMB = 4096; diskGB = 60;
      ip = { k8s = "10.10.40.22"; storage = "10.10.30.32"; };
    };
  };

  # Cloudflare Tunnel for remote admin access (modules/remote-access.nix).
  # Tunnel hgd1-admin; null keeps the module off.
  remoteAccess = {
    tunnelId = "2dc8c4e1-ce31-4429-a07a-6b9759648ae1";
    routes = [ "10.10.0.0/16" ];
  };

  # Laptop key: SSH login and agenix recipient.
  adminKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDfML1tz4bMJ7uAoIS5Hhd3cTE95X5QdaEJ8hR/1gWnE jurre@b302.nl"
  ];
}
