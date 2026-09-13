{ ... }:

{
  # nix-darwin が Homebrew の cask / mas を宣言的に管理する
  # profile 固有の追加は hosts/{profile}.nix 側で homebrew.casks / homebrew.brews に
  # 書き足す (Nix のモジュールシステムがリストを自動でマージする)
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      # rebuild のたびに brew upgrade 相当が走る。auto_updates / version :latest な cask
      # (raycast, shottr 等) は対象外で、必要なら個別に greedy = true を付ける。
      upgrade = true;
      # このファイルと hosts/*.nix に書いていない formula/cask/tap は activate 時に
      # uninstall される。つまり手で brew install したものは次の rebuild で消えるので、
      # 常用するものは必ずここに書き足すこと。
      cleanup = "uninstall";
    };
    taps = [
      # Homebrew 6 以降は非公式 tap を明示的に trust しないと、依存関係の
      # 解決や cleanup が formula/cask を読み込めない。
      { name = "atani/tap"; trusted = true; }
      { name = "daipeihust/tap"; trusted = true; }
      { name = "nandemo-ya/tap"; trusted = true; }
    ];
    # nixpkgs に無いもの (crit, im-select) のみ Homebrew で管理
    brews = [
      "crit"
      "daipeihust/tap/im-select"
      "hiro-o918/tap/rinkaku"
    ];
    # nixpkgs と Homebrew の切り分けは CLAUDE.md「パッケージを nixpkgs で入れるか
    # Homebrew で入れるか」を参照。以下は個別の理由。
    # codex/font-hack-nerd-font は home.nix (nixpkgs) へ移行済み。alacritty は廃止。
    # raycast/shottr は auto_updates (自己更新が Nix store の read-only と衝突するため),
    # karabiner-elements はカーネル拡張/権限まわりのリスクのため brew を継続。
    # 1password-cli は 1Password.app の CLI 統合 (署名検証) が壊れる懸念があるため継続。
    # spotify は nixpkgs にも darwin 版があるが、配布バイナリを
    # store に展開するだけで自己更新と衝突するため cask で管理する。
    # chatgpt は仕事用 Mac のみなので hosts/work.nix へ。
    casks = [
      "1password-cli"
      "alt-tab"
      "karabiner-elements"
      "linearmouse"
      # ドライバ/常駐エージェントを sudo で入れる installer 形式の cask。
      "raycast"
      "shottr"
      "spotify"
      # cask が atani/tap/ctxpack formula を依存関係として導入する。
      "nandemo-ya/tap/ctxpack-mcp"
    ];
  };
}
