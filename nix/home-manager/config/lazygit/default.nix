{ ... }:

{
  # lazygit/config.yml から移行
  programs.lazygit = {
    enable = true;
    settings = {
      git = {
        autocommit = false;
        pagers = [
          {
            colorArg = "always";
            pager = "delta --paging=never --true-color=auto --dark --side-by-side --line-numbers --width=variable --navigate";
          }
        ];
      };
      keybinding.universal.filteringMenu = "<ctrl+g>";
    };
  };
}
