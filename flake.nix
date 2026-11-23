{
  description = "NixOS configs for the hgd1 hypervisors";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    microvm = {
      url = "github:microvm-nix/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, agenix, microvm, ... }:
    let
      system = "x86_64-linux";
      inventory = import ./inventory.nix;
      pkgs = nixpkgs.legacyPackages.${system};
      guestConfigurations = builtins.mapAttrs (vmName: vm:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inventory vmName vm; };
          modules = [ microvm.nixosModules.microvm ./modules/microvm/guest ];
        }) inventory.vms;
    in
    {
      nixosConfigurations = (builtins.mapAttrs (host: _:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inventory guestConfigurations; };
          modules = [
            agenix.nixosModules.default
            microvm.nixosModules.host
            ./hosts/common.nix
            ./modules/network.nix
            ./modules/microvm/host
            ./modules/rollout-safety.nix
            ./modules/ceph.nix
            ./modules/s3-ha
            ./modules/remote-access.nix
            (./hosts + "/${host}")
          ];
        }) inventory.hosts) // guestConfigurations;

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          agenix.packages.${system}.default
          pkgs.cloudflared
          pkgs.jq
          pkgs.kubectl
          pkgs.nmap
          pkgs.nixos-rebuild-ng
          pkgs.shellcheck
        ];
        # Written by scripts/kubeconfig.sh.
        shellHook = ''
          export KUBECONFIG="''${KUBECONFIG:-$HOME/.kube/hgd1.yaml}"
        '';
      };
    };
}
