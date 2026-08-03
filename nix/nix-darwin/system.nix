{ pkgs, username, ... }:

{
  # Nix 自体の設定
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # nixpkgs の設定
  nixpkgs.config.allowUnfree = true;

  # macOS のシステム設定
  system.stateVersion = 6;
  security.pam.services.sudo_local = {
    touchIdAuth = true;
    # tmux サーバは Aqua セッションの bootstrap namespace から切り離されているため、
    # pam_tid.so だけでは tmux 内の sudo が Touch ID ダイアログを出せずパスワードに
    # フォールバックする。pam_reattach.so を前段に挟んで元のセッションに再接続させる。
    reattach = true;
  };

  # home-manager がユーザーを解決するために必要
  system.primaryUser = username;
  users.users.${username}.home = "/Users/${username}";
}
