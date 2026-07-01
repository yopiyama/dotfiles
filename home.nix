{ pkgs, ... }:

{
  home.stateVersion = "25.05";

  # Brewfile の brew 行に対応するパッケージ
  home.packages = with pkgs; [
    awscli2
    bat
    eza
    fd
    findutils
    fzf
    gawk
    gh
    ghq
    git-delta
    gnused
    iproute2
    jq
    lazygit
    mergiraf
    mise
    neovim
    ripgrep
    tmux
    uv
    yq-go
    zsh
  ];
}
