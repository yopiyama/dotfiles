{ pkgs, ... }:

{
  # Nix 自体の設定
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # nixpkgs の設定
  nixpkgs.config.allowUnfree = true;

  # macOS のシステム設定
  system.stateVersion = 6;
  security.pam.services.sudo_local.touchIdAuth = true;

  # home-manager がユーザーを解決するために必要
  system.primaryUser = "yopiyama";
  users.users.yopiyama.home = "/Users/yopiyama";
}
