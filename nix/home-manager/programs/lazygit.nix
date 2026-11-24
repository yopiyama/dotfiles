{ ... }:

{
  # lazygit/config.yml から移行
  programs.lazygit = {
    enable = true;
    settings = {
      # ハンク単位だと最後のハンク内を j/k で読み進められないため、行単位で開く。
      # ハンク単位の選択は a で切り替える。
      gui.useHunkModeInDiffView = false;
      os.editPreset = "nvim-remote";
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
