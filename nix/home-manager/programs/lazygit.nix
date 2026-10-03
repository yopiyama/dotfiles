{ ... }:

{
  # lazygit/config.yml から移行
  programs.lazygit = {
    enable = true;
    settings = {
      git = {
        autocommit = false;
        diffRenderers = [
          {
            colorArg = "always";
            # wrap-max-lines: delta のデフォルト(2)だと長い行が折り返し 2 行で切り捨てられる
            command = "delta --paging=never --true-color=auto --dark --side-by-side --line-numbers --width=variable --navigate --wrap-max-lines=unlimited";
          }
        ];
      };
      keybinding.universal.filteringMenu = "<ctrl+g>";
    };
  };
}
