{ pkgs, username, ... }:

{
  home.stateVersion = "25.05";
  home.username = username;
  home.homeDirectory = "/Users/${username}";

  # Brewfile の brew 行に対応するパッケージ
  home.packages = with pkgs; [
    awscli2
    bat
    delta
    eza
    fd
    findutils
    fzf
    gawk
    gh
    ghq
    gnused
    iproute2mac
    jq
    lazygit
    markdownlint-cli
    mergiraf
    mise
    neovim
    prettier
    ripgrep
    tmux
    uv
    yamllint
    yq-go
    zsh
  ];
}
