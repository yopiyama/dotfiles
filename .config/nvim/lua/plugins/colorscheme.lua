return {
  "folke/tokyonight.nvim",
  lazy = false,
  priority = 1000,
  config = function()
    require("tokyonight").setup({
      style = "moon",
      on_highlights = function(hl, c)
        -- 既定の LineNr は fg_gutter (#3b4261) で bg とのコントラストが低すぎるので持ち上げる
        hl.LineNr = { fg = c.dark5 }
        hl.LineNrAbove = { fg = c.dark5 }
        hl.LineNrBelow = { fg = c.dark5 }
        -- カーソル行の番号は CursorLine と地続きに見せて現在位置を掴みやすくする
        hl.CursorLineNr = { fg = c.orange, bg = c.bg_highlight, bold = true }
      end,
    })
    vim.cmd.colorscheme("tokyonight")
  end,
}
