{ pkgs, username, ... }:

{
  # Nix 自体の設定
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # nixpkgs の設定
  nixpkgs.config.allowUnfree = true;

  # nix-darwin が /etc/zshenv 経由で EDITOR=nano を入れてくるため上書きする。
  # git commit --amend などのエディタ起動を nvim にする。
  environment.variables.EDITOR = "nvim";

  # macOS のシステム設定
  system.stateVersion = 6;
  security.pam.services.sudo_local = {
    touchIdAuth = true;
  };

  # Dock は使わないので実質的に画面へ出さない。完全に無効化する手段は無いため
  # autohide + 表示までの待ち時間を極端に長くすることで代用する。
  # 一時的に出したくなったら Cmd+Option+D で autohide を切る。
  system.defaults.dock = {
    autohide = true;

    # 画面端へカーソルを移動してから Dock が出るまでの秒数。
    # 1000 秒 (約 17 分) にして事実上出てこないようにする。
    autohide-delay = 1000.0;

    # 隠れるアニメーションを即時化
    autohide-time-modifier = 0.0;
  };

  # アクセシビリティの Zoom: 修飾キー + スクロールで画面を拡大する。
  # キーボードショートカットでの Zoom は使わない (shortcuts.nix で無効)。
  # 修飾キーの専用オプションは無いため CustomUserPreferences で指定する (1048576 = Cmd)。
  # com.apple.universalaccess への書き込みは、rebuild を実行するターミナルに
  # フルディスクアクセスが無いと拒否されることがある。
  system.defaults.universalaccess.closeViewScrollWheelToggle = true;
  system.defaults.CustomUserPreferences = {
    "com.apple.universalaccess".closeViewScrollWheelModifiersInt = 1048576;
    "com.apple.AppleMultitouchTrackpad".HIDScrollZoomModifierMask = 1048576;
    "com.apple.driver.AppleBluetoothMultitouch.trackpad".HIDScrollZoomModifierMask = 1048576;
  };

  # トラックパッド。nix-darwin が内蔵 (AppleMultitouchTrackpad) と Bluetooth
  # (AppleBluetoothMultitouch.trackpad) の両ドメインへ同じ値を書く。
  # 既定値のままの項目 (四本指ジェスチャなど) は宣言していない。
  system.defaults.trackpad = {
    Clicking = true; # タップでクリック
    TrackpadRightClick = true; # 二本指クリックで副ボタン
    TrackpadThreeFingerDrag = true; # 三本指ドラッグ
    TrackpadThreeFingerTapGesture = 2; # 三本指タップで調べる
    Dragging = false;
    DragLock = false;
    FirstClickThreshold = 1; # クリックの強さ: 中
    SecondClickThreshold = 1; # 強めのクリックの強さ: 中
  };

  # home-manager がユーザーを解決するために必要
  system.primaryUser = username;
  users.users.${username}.home = "/Users/${username}";
}
