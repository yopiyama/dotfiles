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
        window = {
            mappings = {
                -- デフォルトの f (fuzzy_finder) を / に逃がし、<leader>f* を telescope 用に空ける
                ["f"] = "none",
                ["/"] = "fuzzy_finder",
                -- <leader> がスペースなので neo-tree の toggle_node と競合する。
                -- スペースを無効化し、ディレクトリ開閉は <CR>(Enter) で代用する
                ["<space>"] = "none",
            },
        },
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
              ".terraform",
              ".DS_Store",
            },
            -- visible = true でも .git は常に非表示にする
            never_show = {
              ".git",
            },
          },
        },
      })
    end,
    lazy = false,
  }
}
