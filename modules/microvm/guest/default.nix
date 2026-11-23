# Base VM runtime only; k3s installation/join remains a separate step.
{ lib, pkgs, vm, ... }:
let
  net = (import ../../../lib/vm-network.nix { inherit lib; }).networkFor vm;
in
{
  imports = [
    ./networking.nix
    ./access.nix
  ];

  # Ceph 20's kernel-client auth cipher needs Linux >= 7. Guest kernel only.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Read-only host store; only /var/lib persists on the host's NVMe image.
  microvm = {
    hypervisor = "qemu";
    vcpu = vm.vcpu;
    mem = vm.memMB;
    interfaces = [
      {
        type = "tap";
        id = net.k8s.tap;
        mac = net.k8s.mac;
        tap.vhost = true;
      }
      {
        type = "tap";
        id = net.storage.tap;
        mac = net.storage.mac;
        tap.vhost = true;
      }
    ];
    shares = [
      {
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
        tag = "ro-store";
        proto = "virtiofs";
        readOnly = true;
      }
    ];
    volumes = [
      {
        image = "var-lib.img";
        mountPoint = "/var/lib";
        size = vm.diskGB * 1024;
        fsType = "ext4";
      }
    ];
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  services.timesyncd.enable = true;
  services.journald.extraConfig = "SystemMaxUse=128M";
  system.stateVersion = "26.05";
}
