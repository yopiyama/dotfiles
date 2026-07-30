return {
  {
    "nvim-neo-tree/neo-tree.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      "nvim-tree/nvim-web-devicons",
      "s1n7ax/nvim-window-picker",
    },
    config = function()
      require("neo-tree").setup({
        event_handlers = {
          {
            -- neo-tree を開いたら自動で preview mode に入る。
            -- preview mode は use_float = true でカーソル行のファイルを
            -- floating window に追従表示する（P = toggle_preview をエミュレート）。
            event = "neo_tree_window_after_open",
            handler = function(args)
              vim.schedule(function()
                if args.winid and vim.api.nvim_win_is_valid(args.winid) then
                  vim.api.nvim_set_current_win(args.winid)
                  vim.api.nvim_feedkeys("P", "m", false)
                end
              end)
            end,
          },
        },
        window = {
            position = "float",
            -- float のサイズ・位置を調整する場合はここ
            -- popup = {
            --     size = { width = "60%", height = "80%" },
            --     position = "50%",
            -- },
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
            },
            -- visible = true でも .git は常に非表示にする
            never_show = {
              ".git",
              ".DS_Store",
            },
          },
        },
      })
    end,
    lazy = false,
  }
}
