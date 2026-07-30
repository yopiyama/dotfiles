{ pkgs, ... }:

{
  # Nix 自体の設定
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # nixpkgs の設定
  nixpkgs.config.allowUnfree = true;

  # macOS のシステム設定
  system.stateVersion = 6;
  security.pam.services.sudo_local.touchIdAuth = true;

  # nix-darwin が Homebrew の cask / mas を宣言的に管理する
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "none";
    };
    taps = [
      "daipeihust/tap"
    ];
    # nixpkgs に無いもの (crit, im-select) のみ Homebrew で管理
    brews = [
      "crit"
      "daipeihust/tap/im-select"
    ];
    casks = [
      "1password-cli"
      "alacritty"
      "alt-tab"
      "codex"
      "font-hack-nerd-font"
      "karabiner-elements"
      "linearmouse"
      "raycast"
      "shottr"
    ];
  };
}
