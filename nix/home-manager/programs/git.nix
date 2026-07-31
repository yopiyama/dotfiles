{ ... }:

{
  # .config/git/{config,ignore,attributes} から移行
  programs.git = {
    enable = true;

    includes = [
      { path = "~/.config/git/config.local"; }
    ];

    ignores = [
      "bin/"
      "!cdk/bin/"
      ".DS_Store"
      "*.swp"
      "__pycache__"
      "*.out"
      "*.exe"
      "tmp.*"
      "tmp/"
      "tmp*"
      "*.icloud"
      ".sass-cache/"
      "*.zip"
      "*.dSYM/"
      "*.link"
      "export/"
      "*.log"
      "*.blg"
      "*.toc"
      "*.dvi"
      "*.bbl"
      "*.orig"
      "*.aux"
      "*(busy)"
      "*.synctex.gz"
      "*.fls"
      "*.lof"
      "*.lot"
      "cert/"
      "*~"
      "~*"
      "*~/"
      "~*/"
      ".env"
      "*.env"
      "python/*"
      "layer/"
      "*.base64sha256.txt"
      ".ansible/"
      "**/settings.local.json"
      ".serena/cache/"
      ".idea/"
      ".claude/worktrees/"
    ];

    attributes = [
      "* merge=mergiraf"
    ];

    settings = {
      init.defaultBranch = "main";
      core.pager = "delta";
      delta = {
        side-by-side = true;
        features = "unobtrusive-line-numbers decorations";
        whitespace-error-style = "22 reverse";
      };
      "delta \"unobtrusive-line-numbers\"" = {
        line-numbers = true;
        line-numbers-left-format = "{nm:>4}┊";
        line-numbers-right-format = "{np:>4}│";
        line-numbers-left-style = "blue";
        line-numbers-right-style = "blue";
      };
      "delta \"decorations\"" = {
        commit-decoration-style = "box ul";
      };
      "merge \"mergiraf\"" = {
        name = "mergiraf";
        driver = "mergiraf merge --git %O %A %B -s %S -x %X -y %Y -p %P -l %L";
      };
    };
  };
}
