{ pkgs, username, ... }:

{
  # 仕事用 Mac 固有の設定。
  # homebrew.casks / homebrew.brews はリスト型オプションなので、
  # homebrew.nix の共通設定と自動でマージされる (++ で結合される)。

  # 仕事用 Mac だけで使う設定。両方の Mac で使うものは home-manager/home.nix へ。
  # (${username} は動的な属性名なので、この attrset は 1 つにまとめる必要がある)
  home-manager.users.${username} = {
    home.packages = with pkgs; [
      # aws ssm start-session が PATH から呼ぶ session-manager-plugin 本体
      # (Homebrew の cask session-manager-plugin と同じもの)。
      ssm-session-manager-plugin

      # GKE のクラスタを覗く TUI。仕事でしか Kubernetes を触らないため
      # 共通ではなくこちらに置く。
      k9s
    ];

    # GKE を触るのに必要な gcloud のコンポーネント。gcloud 本体は
    # home-manager/programs/google-cloud-sdk.nix (共通) 側で入れている。
    # gke-gcloud-auth-plugin は kubeconfig の exec からバイナリ名で呼ばれるため、
    # 単体パッケージが無い以上 gcloud への同梱以外に入れる手段がない。
    dotfiles.googleCloudSdk.extraComponents = with pkgs.google-cloud-sdk.components; [
      kubectl
      gke-gcloud-auth-plugin
    ];
  };

  homebrew = {
    casks = [
      # 自己更新するため nixpkgs ではなく cask で管理する。
      "chatgpt"
      "tableplus"
      "firefox"
      "meetingbar"
      "postman"
      "redis-insight"
    ];
  };
}
