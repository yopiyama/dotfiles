{ ... }:

{
  # nix-darwin が Homebrew の cask / mas を宣言的に管理する
  # profile 固有の追加は hosts/{profile}.nix 側で homebrew.casks / homebrew.brews に
  # 書き足す (Nix のモジュールシステムがリストを自動でマージする)
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
    # alacritty/codex/font-hack-nerd-font は home.nix (nixpkgs) へ移行済み。
    # raycast/shottr は auto_updates (自己更新が Nix store の read-only と衝突するため),
    # karabiner-elements はカーネル拡張/権限まわりのリスクのため brew を継続。
    # 1password-cli は 1Password.app の CLI 統合 (署名検証) が壊れる懸念があるため継続。
    casks = [
      "1password-cli"
      "alt-tab"
      "karabiner-elements"
      "linearmouse"
      "raycast"
      "shottr"
    ];
  };
}
