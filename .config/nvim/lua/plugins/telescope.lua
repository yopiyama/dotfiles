return {
    {
        "nvim-telescope/telescope.nvim",
        branch = "0.1.x",
        dependencies = {
            "nvim-lua/plenary.nvim",
            { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
        },
        config = function()
            local telescope = require("telescope")

            -- ここに追記したパターンに一致するファイル/ディレクトリは検索結果から除外される
            -- (Lua パターンで file_ignore_patterns に渡される。柔軟に増やせる)
            local ignore_patterns = {
                "%.git/",
                "node_modules/",
                "%.DS_Store",
            }

            telescope.setup({
                defaults = {
                    -- 隠しファイルも対象にしつつ上記パターンを除外する
                    file_ignore_patterns = ignore_patterns,
                    -- live_grep / grep_string でも隠しファイルを検索対象にする
                    -- (.git ディレクトリは rg 側でも除外して高速化)
                    vimgrep_arguments = {
                        "rg",
                        "--color=never",
                        "--no-heading",
                        "--with-filename",
                        "--line-number",
                        "--column",
                        "--smart-case",
                        "--hidden",
                        "--glob=!**/.git/*",
                    },
                    mappings = {
                        i = {
                            ["<C-j>"] = "move_selection_next",
                            ["<C-k>"] = "move_selection_previous",
                        },
                    },
                },
                pickers = {
                    find_files = {
                        -- 隠しファイル(ドットファイル)を表示する
                        hidden = true,
                    },
                },
            })
            pcall(telescope.load_extension, "fzf")

            local builtin = require("telescope.builtin")
            vim.keymap.set("n", "<leader>ff", builtin.find_files, { desc = "Find files" })
            vim.keymap.set("n", "<leader>fg", builtin.live_grep, { desc = "Live grep" })
            vim.keymap.set("n", "<leader>fb", builtin.buffers, { desc = "Buffers" })
            vim.keymap.set("n", "<leader>fh", builtin.help_tags, { desc = "Help tags" })
        end,
    },
}
