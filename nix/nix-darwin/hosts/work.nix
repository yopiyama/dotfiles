{ pkgs, username, ... }:

{
  # 仕事用 Mac 固有の設定。
  # homebrew.casks / homebrew.brews はリスト型オプションなので、
  # homebrew.nix の共通設定と自動でマージされる (++ で結合される)。

  # 仕事用 Mac だけで使うパッケージ。両方の Mac で使うものは home-manager/home.nix へ。
  home-manager.users.${username}.home.packages = with pkgs; [
    gemini-cli
    # aws ssm start-session が PATH から呼ぶ session-manager-plugin 本体
    # (Homebrew の cask session-manager-plugin と同じもの)。
    ssm-session-manager-plugin
  ];

  homebrew = {
    casks = [
      "firefox"
      "meetingbar"
      "redis-insight"
    ];
  };
}
