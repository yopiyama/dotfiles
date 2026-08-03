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
    # tmux サーバは Aqua セッションの bootstrap namespace から切り離されているため、
    # pam_tid.so だけでは tmux 内の sudo が Touch ID ダイアログを出せずパスワードに
    # フォールバックする。pam_reattach.so を前段に挟んで元のセッションに再接続させる。
    reattach = true;
  };

  # home-manager がユーザーを解決するために必要
  system.primaryUser = username;
  users.users.${username}.home = "/Users/${username}";
}
