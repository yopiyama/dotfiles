{ ... }:

{
  # リポジトリごとの nix devShell (例: 社内リポジトリの flake.nix) を cd だけで読ませる。
  # .envrc は各リポジトリ側に置く前提なので、ここには個別のパスを書かない。
  programs.direnv = {
    enable = true;

    # devShell の評価結果をキャッシュし、nix store gc で消えないようにする
    nix-direnv.enable = true;

    # zsh は home-manager 管理外 (.zshrc は scripts/link.sh の symlink) なので
    # この統合は何も生成しない。hook は .zshrc の末尾に直接書いている。
    enableZshIntegration = false;
  };
}
