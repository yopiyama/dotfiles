{ ... }:

{
  # ~/.config/gh/config.yml, ~/.config/git/config.local の credential から移行
  programs.gh = {
    enable = true;

    settings = {
      git_protocol = "https";
      aliases = {
        co = "pr checkout";
      };
    };

    # helper は ${pkgs.gh}/bin/gh の store path で出力されるため、
    # プロファイル配置 (/etc/profiles/... か ~/.nix-profile/...) に依存しない。
    # GUI アプリ (Obsidian 等) が spawn する git のように PATH に nix が入らない
    # 環境でも credential helper が解決できる。
    # hosts の default が github.com + gist.github.com で現状の設定と一致するので指定しない。
    gitCredentialHelper.enable = true;
  };

  # hosts.yml は OAuth トークンを持つので nix 管理下に置かない。
  # programs.gh.hosts を空のままにすると書き込み可のまま残り、gh auth login が使える。
}
