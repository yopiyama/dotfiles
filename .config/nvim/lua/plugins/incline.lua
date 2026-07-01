return {
  {
    "b0o/incline.nvim",
    dependencies = "nvim-tree/nvim-web-devicons",
    event = "VeryLazy",
    opts = {
      window = {
        padding = 0,
        margin = { horizontal = 0 },
      },
      render = function(props)
        local helpers = require("incline.helpers")
        local devicons = require("nvim-web-devicons")

        local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(props.buf), ":t")
        if filename == "" then
          filename = "[No Name]"
        end
        local ft_icon, ft_color = devicons.get_icon_color(filename)
        local modified = vim.bo[props.buf].modified

        -- フォーカス中のウィンドウのバッジだけ目立たせる（tokyonight moon の palette に合わせた配色）
        local bg = props.focused and "#44406e" or "#1e2030"
        local fg = props.focused and "#c8d3f5" or "#565f89"

        return {
          ft_icon and { " ", ft_icon, " ", guibg = ft_color, guifg = helpers.contrast_color(ft_color) } or "",
          " ",
          { filename, gui = modified and "bold,italic" or "bold", guifg = fg },
          " ",
          guibg = bg,
        }
      end,
    },
  },
}
