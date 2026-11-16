{
  description = "Minimal NixOS configs for pve0, pve1 and pve2";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { nixpkgs, ... }: {
    nixosConfigurations = builtins.listToAttrs (map (host: {
      name = host;
      value = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./hosts/common.nix (./hosts + "/${host}") ];
      };
    }) [ "pve0" "pve1" "pve2" ]);
  };
}
