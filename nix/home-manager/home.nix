{ pkgs, username, ... }:

{
  imports = [
    ./programs/alacritty.nix
    ./programs/direnv.nix
    ./programs/gh.nix
    ./programs/ghostty.nix
    ./programs/git.nix
    ./programs/lazygit.nix
    ./programs/mise.nix
  ];

  home.stateVersion = "25.05";
  home.username = username;
  home.homeDirectory = "/Users/${username}";

  # Brewfile の brew 行に対応するパッケージ
  # alacritty/mise/lazygit/gh は programs.* が自動で追加するのでここには書かない
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
    ghq
    gnused
    golangci-lint
    gotools # goimports (nvim の保存時に import を追加/削除する)
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
