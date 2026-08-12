{ pkgs, ... }:

{
  # Alacritty からの乗り換え検討用。動作確認が済むまで alacritty.nix は残したまま併存させる。
  programs.ghostty = {
    enable = true;

    # pkgs.ghostty は Linux 専用 (darwin では meta.unsupported) なので、
    # 公式配布の .dmg をそのまま展開する ghostty-bin を使う。
    # Ghostty.app は他の nixpkgs 製 GUI アプリ (Alacritty) と同じく
    # ~/Applications/Home Manager Apps/ 配下に置かれる。
    package = pkgs.ghostty-bin;

    # zsh は symlink 管理の .zshrc であって home-manager の programs.zsh は使っていないため、
    # HM 側から shell integration を注入しても書き込み先が無い。Ghostty 本体が
    # 起動時に行う自動 injection (shell-integration = detect) に任せる。
    enableZshIntegration = false;
    # programs.bat も未使用 (bat は home.packages から入れているだけ) なので無効化。
    installBatSyntax = false;

    settings = {
      # ---- alacritty.nix からの移行分 ----
      font-family = "Hack Nerd Font Mono";
      font-size = 14;

      # タイトルバーごと消す (Ghostty はタイトルバーにお化けアイコンとタイトルを出すため)。
      # 信号機ボタンも一緒に消えるので macos-window-buttons は不要。
      # トレードオフ: 上端でウィンドウをドラッグできなくなる。移動はウィンドウ枠を
      # option+click でドラッグする (macOS 標準の挙動で Ghostty 固有の制限ではない)。
      # Alacritty の decorations = "Buttonless" に寄せたい (タイトルバーは残して
      # ボタンだけ消す) なら macos-titlebar-style = "transparent" +
      # macos-window-buttons = "hidden" に戻す。
      macos-titlebar-style = "hidden";

      # option_as_alt = "Both" 相当 (left/right の片側だけにもできる)。
      macos-option-as-alt = true;

      window-padding-x = 4;
      window-padding-y = 4;
      # Alacritty の window.dynamic_padding 相当。余りを左右/上下に均等配分する。
      window-padding-balance = true;

      mouse-hide-while-typing = false;

      # Ghostty のデフォルトは xterm-ghostty。ローカルには terminfo が同梱されるので
      # 問題ないが、ssh 先に xterm-ghostty が無いと表示が崩れるため Alacritty と同じ
      # xterm-256color に揃える。tmux 内は .tmux.conf の default-terminal が優先される。
      term = "xterm-256color";

      # Alacritty の bell.command (afplay Ping.aiff) 相当。
      # 併せて Dock アイコンのバウンス (attention) とタイトルへのマーク (title) を有効化。
      # ここに書いた項目以外 (system, border) は自動的に無効になる。
      bell-features = "audio,attention,title";
      bell-audio-path = "/System/Library/Sounds/Ping.aiff";

      # URL の Cmd+Click オープンは link-url = true (デフォルト) で標準で効くため、
      # Alacritty の hints 相当の設定は不要。

      keybind = [
        # IME 切り替えキー (Ctrl+Space → Karabiner → Ctrl+Shift+S / IME 側の Ctrl+Alt+S) が
        # ^S として pty に流れ、nvim/Telescope の <C-s> マッピングを誤爆させるのを防ぐ。
        # 素の Ctrl+S はそのまま通る。
        "ctrl+shift+s=ignore"
        "ctrl+alt+s=ignore"
        # NOTE: alacritty.nix にある「Ctrl+P (tmux leader) を押したら im-select で ATOK を
        # 英字モードへ強制切り替え」は Ghostty には移植できない。Ghostty の keybind には
        # 外部コマンドを起動するアクションが無い (+list-actions 参照)。
        # 代替案: Karabiner 側で Ghostty (com.mitchellh.ghostty) に限定した
        # select_input_source 付きのルールを足す。
      ];

      # Sparkle による自己更新は Nix store が read-only なので必ず失敗する。
      # 更新は flake.lock (make update) 側で行う。
      auto-update = "off";
    };
  };
}
