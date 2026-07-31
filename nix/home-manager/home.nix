{ pkgs, username, ... }:

{
  imports = [
    ./programs/git.nix
    ./programs/lazygit.nix
    ./programs/mise.nix
  ];

  home.stateVersion = "25.05";
  home.username = username;
  home.homeDirectory = "/Users/${username}";

  # Brewfile の brew 行に対応するパッケージ
  # mise/lazygit は programs.mise / programs.lazygit が自動で追加するのでここには書かない
  home.packages = with pkgs; [
    alacritty
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
