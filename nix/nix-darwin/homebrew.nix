{ ... }:

{
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
