{
  description = "yopiyama's dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, nix-darwin, home-manager, ... }:
    let
      mkSystem = profile: nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs = { inherit profile; };
        modules = [
          ./system.nix
          ./homebrew.nix
          ./hosts/${profile}.nix
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.yopiyama = import ../home-manager/home.nix;
          }
        ];
      };
    in {
      darwinConfigurations = {
        personal = mkSystem "personal";
        work = mkSystem "work";
      };
    };
}
