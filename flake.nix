{
  description = "NixOS configs for the hgd1 hypervisors";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, agenix, ... }:
    let
      system = "x86_64-linux";
      inventory = import ./inventory.nix;
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      nixosConfigurations = builtins.mapAttrs (host: _:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inventory; };
          modules = [
            agenix.nixosModules.default
            ./hosts/common.nix
            ./modules/network.nix
            ./modules/rollout-safety.nix
            ./modules/ceph.nix
            ./modules/remote-access.nix
            (./hosts + "/${host}")
          ];
        }) inventory.hosts;

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          agenix.packages.${system}.default
          pkgs.cloudflared
          pkgs.jq
          pkgs.nmap
          pkgs.nixos-rebuild-ng
          pkgs.shellcheck
        ];
      };
    };
}
