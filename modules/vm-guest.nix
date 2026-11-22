# Base VM OS only. k3s installation/join is a separate step.
{ lib, pkgs, inventory, vmName, vm, ... }:
let
  net = (import ./vm-lib.nix { inherit lib; }).networkFor vm;
  prefix = toString inventory.prefixLength;
  key = "/var/lib/ssh/ssh_host_ed25519_key";
in
{
  networking = {
    hostName = vmName;
    domain = inventory.site.domain;
    useDHCP = false;
    useNetworkd = true;
    nameservers = [ inventory.vlans.k8s.gateway ];
    search = [ inventory.site.domain ];
    timeServers = [ inventory.vlans.k8s.gateway ];
    firewall = {
      enable = true;
      # Match a stable guest name, not PCI probe order.
      interfaces.k8s.allowedTCPPorts = [ 22 ];
    };
  };

  # Kernel Ceph clients in step 4 need Linux >= 7 for Ceph 20's auth cipher.
  # This changes guest kernels only; host kernels/boot configuration stay put.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  systemd.network = {
    enable = true;
    links = {
      "10-k8s" = {
        matchConfig.MACAddress = net.k8s.mac;
        linkConfig.Name = "k8s";
      };
      "10-storage" = {
        matchConfig.MACAddress = net.storage.mac;
        linkConfig.Name = "storage";
      };
    };
    networks = {
      "20-k8s" = {
        matchConfig.Name = "k8s";
        address = [ "${vm.ip.k8s}/${prefix}" ];
        gateway = [ inventory.vlans.k8s.gateway ];
        dns = [ inventory.vlans.k8s.gateway ];
        domains = [ inventory.site.domain ];
        networkConfig = { IPv6AcceptRA = false; LinkLocalAddressing = "no"; };
      };
      "20-storage" = {
        matchConfig.Name = "storage";
        address = [ "${vm.ip.storage}/${prefix}" ];
        # Storage is connected-only: no gateway, DNS or default route.
        networkConfig = { IPv6AcceptRA = false; LinkLocalAddressing = "no"; };
      };
    };
  };

  users = {
    mutableUsers = false;
    users.jurre = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = inventory.adminKeys;
    };
  };
  security.sudo.wheelNeedsPassword = false;
  services.openssh = {
    enable = true;
    openFirewall = false;
    hostKeys = [ { path = key; type = "ed25519"; } ];
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };
  # Public keys only: report through the trusted hypervisor's serial journal
  # so initial SSH trust need not depend on blindly accepting a network scan.
  systemd.services.vm-host-key-report = {
    wantedBy = [ "multi-user.target" ];
    after = [ "sshd.service" ];
    requires = [ "sshd.service" ];
    serviceConfig = { Type = "oneshot"; StandardOutput = "journal+console"; };
    script = ''
      printf 'VM_HOST_KEY ${vmName} %s\n' "$(cat ${key}.pub)"
    '';
  };

  microvm = {
    hypervisor = "qemu";
    vcpu = vm.vcpu;
    mem = vm.memMB;
    interfaces = [
      { type = "tap"; id = net.k8s.tap; mac = net.k8s.mac; tap.vhost = true; }
      { type = "tap"; id = net.storage.tap; mac = net.storage.mac; tap.vhost = true; }
    ];
    shares = [ {
      source = "/nix/store";
      mountPoint = "/nix/.ro-store";
      tag = "ro-store";
      proto = "virtiofs";
      readOnly = true;
    } ];
    volumes = [ {
      image = "var-lib.img";
      mountPoint = "/var/lib";
      size = vm.diskGB * 1024;
      fsType = "ext4";
    } ];
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  services.timesyncd.enable = true;
  services.journald.extraConfig = "SystemMaxUse=128M";
  system.stateVersion = "26.05";
}
