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
      mkSystem = hostFile: nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [
          ./system.nix
          ./homebrew.nix
          hostFile
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
        personal = mkSystem ./hosts/personal.nix;
        work = mkSystem ./hosts/work.nix;
      };
    };
}
