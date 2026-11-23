# Key-only guest administration with persistent SSH host identity.
{ inventory, vmName, ... }:
let
  key = "/var/lib/ssh/ssh_host_ed25519_key";
in
{
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
    hostKeys = [
      {
        path = key;
        type = "ed25519";
      }
    ];
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # Public keys only, through the trusted hypervisor's serial journal.
  # Initial SSH trust must not depend on blindly accepting a network scan.
  systemd.services.vm-host-key-report = {
    wantedBy = [ "multi-user.target" ];
    after = [ "sshd.service" ];
    requires = [ "sshd.service" ];
    serviceConfig = {
      Type = "oneshot";
      StandardOutput = "journal+console";
    };
    script = ''
      printf 'VM_HOST_KEY ${vmName} %s\n' "$(cat ${key}.pub)"
    '';
  };
}
