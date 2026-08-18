{ pkgs, username, ... }:

{
  # 私用 Mac 固有の設定。
  # homebrew.casks / homebrew.brews はリスト型オプションなので、
  # homebrew.nix の共通設定と自動でマージされる (++ で結合される)。

  # 私用 Mac だけで使うパッケージ。両方の Mac で使うものは home-manager/home.nix へ。
  home-manager.users.${username}.home.packages = with pkgs; [
    # Docker / Linux VM。dmg を展開して ~/Applications 配下に置くだけの derivation で、
    # docker/kubectl/orbctl の補完と bin も PATH に載る。
    # アプリ内の自己更新は Nix store が read-only なので必ず失敗する。設定画面で
    # 自動更新をオフにすること。更新は flake.lock (make update) 側で行う。
    orbstack
  ];
}
