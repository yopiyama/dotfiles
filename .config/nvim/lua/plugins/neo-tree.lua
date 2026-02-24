return {
  {
    "nvim-neo-tree/neo-tree.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      "nvim-tree/nvim-web-devicons",
    },
    config = function()
      require("neo-tree").setup({
        filesystem = {
          bind_to_cwd = true,
          cwd_target = {
            sidebar = "global",
            current = "global",
          },
          filtered_items = {
            visible = true,
            hide_dotfiles = false,
            hide_gitignored = false,
            hide_by_name = {
              ".git",
              ".terraform",
              ".DS_Store",
            },
          },
        },
      })
    end,
    lazy = false,
  }
}
