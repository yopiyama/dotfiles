{ pkgs, username, ... }:

{
  imports = [
    ./config/alacritty
    ./config/git
    ./config/lazygit
    ./config/mise
  ];

  home.stateVersion = "25.05";
  home.username = username;
  home.homeDirectory = "/Users/${username}";

  # Brewfile の brew 行に対応するパッケージ
  # alacritty/mise/lazygit は programs.* が自動で追加するのでここには書かない
  home.packages = with pkgs; [
    awscli2
    bat
    codex
    delta
    eza
    fd
    findutils
    fzf
    gawk
    gh
    ghq
    gnused
    golangci-lint
    iproute2mac
    jq
    markdownlint-cli
    mergiraf
    neovim
    nerd-fonts.hack
    prettier
    ripgrep
    ruff
    shellcheck
    tmux
    uv
    yamllint
    yq-go
    zsh
  ];
}
