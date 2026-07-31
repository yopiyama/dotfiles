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
      mkSystem = { profile, username }: nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs = { inherit profile username; };
        modules = [
          ./system.nix
          ./homebrew.nix
          ./hosts/${profile}.nix
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            # scripts/link.sh の symlink 等、既存ファイルと衝突した場合はエラーで止めず
            # *.bak にリネームしてから home-manager 管理下に置き換える
            # (両層で同じパスを管理すると symlink が黙って退避されるので注意)
            home-manager.backupFileExtension = "bak";
            home-manager.extraSpecialArgs = { inherit username; };
            home-manager.users.${username} = import ../home-manager/home.nix;
          }
        ];
      };
    in {
      darwinConfigurations = {
        personal = mkSystem { profile = "personal"; username = "yopiyama"; };
        # 実際の macOS アカウント名が判明したら username を更新する
        work = mkSystem { profile = "work"; username = "yopiyama"; };
      };
    };
}
