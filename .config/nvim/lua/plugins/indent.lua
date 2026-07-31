-- インデントの可視化
-- ibl: インデントレベルごとに色を変えたガイド線 (VSCode の indent rainbow 相当)
-- hlchunk: カーソルのいるブロックを枠線で囲む (VSCode の Blockman 相当)

-- tokyonight moon のパレット (lua/plugins/colorscheme.lua と揃える)
local rainbow = {
  IndentRainbowRed = "#ff757f",
  IndentRainbowOrange = "#ff966c",
  IndentRainbowYellow = "#ffc777",
  IndentRainbowGreen = "#c3e88d",
  IndentRainbowCyan = "#86e1fc",
  IndentRainbowBlue = "#82aaff",
  IndentRainbowPurple = "#c099ff",
}

-- インデントの深さの順に適用される
local highlight = {
  "IndentRainbowRed",
  "IndentRainbowOrange",
  "IndentRainbowYellow",
  "IndentRainbowGreen",
  "IndentRainbowCyan",
  "IndentRainbowBlue",
  "IndentRainbowPurple",
}

return {
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      local hooks = require("ibl.hooks")

      -- colorscheme の切り替えで消えないよう HIGHLIGHT_SETUP フックで定義する
      hooks.register(hooks.type.HIGHLIGHT_SETUP, function()
        for name, fg in pairs(rainbow) do
          vim.api.nvim_set_hl(0, name, { fg = fg })
        end
      end)

      require("ibl").setup({
        indent = {
          char = "▏",
          highlight = highlight,
        },
        -- 現在スコープの表示は hlchunk の枠線に任せる (二重に強調すると煩いため)
        scope = { enabled = false },
        exclude = {
          filetypes = {
            "help",
            "lazy",
            "neo-tree",
            "Trouble",
            "lazygit",
            "octo",
            "markdown",
          },
        },
      })
    end,
  },
  {
    "shellRaining/hlchunk.nvim",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      require("hlchunk").setup({
        chunk = {
          enable = true,
          style = {
            { fg = "#82aaff" }, -- 通常
            { fg = "#ff757f" }, -- 括弧が閉じていないとき
          },
          exclude_filetypes = {
            help = true,
            lazy = true,
            ["neo-tree"] = true,
            octo = true,
            markdown = true,
          },
        },
        -- indent / blank / line_num は ibl と役割が重複するので無効のまま
      })
    end,
  },
}
