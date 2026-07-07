return {
  "nvim-lualine/lualine.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  event = "VeryLazy",
  config = function()
    require("lualine").setup({
      options = {
        theme = "tokyonight",
        -- statusline を window ごとではなく画面全幅の 1 本にする (laststatus=3)。
        -- split で window が狭くてもブランチ名やファイル名が潰れない。
        -- 各 window のファイル名表示は incline が担当している
        globalstatus = true,
      },
      sections = {
        lualine_b = { "branch", "diff", "diagnostics" },
        lualine_c = {
          -- 全幅になった分、ファイル名は相対パス付きで表示
          { "filename", path = 1 },
        },
        -- 検索カウント [3/14] を常時表示 (nohlsearch で消える)
        lualine_x = { "searchcount", "encoding", "fileformat", "filetype" },
      },
    })
  end,
}
