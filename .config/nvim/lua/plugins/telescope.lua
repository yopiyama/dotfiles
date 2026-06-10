return {
    {
        "nvim-telescope/telescope.nvim",
        tag = "0.1.8",
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
                    -- ファイルパスを幅に合わせて切り詰めて表示する
                    path_display = { "truncate" },
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
                    -- ファイル名の表示幅を広げる （デフォルト 30）
                    lsp_reference = {
                        fname_width = 60
                    },
                    lsp_definitions = {
                        fname_width = 60
                    },
                    lsp_implementations = {
                        fname_width = 60
                    }
                },
            })
            pcall(telescope.load_extension, "fzf")

            local builtin = require("telescope.builtin")
            -- Find
            vim.keymap.set("n", "<leader>ff", builtin.find_files, { desc = "Find files" })
            vim.keymap.set("n", "<leader>fg", builtin.live_grep, { desc = "Live grep" })
            -- Scoped search: ディレクトリを都度指定して検索
            vim.keymap.set("n", "<leader>fF", function()
                local dir = vim.fn.input("Find files in: ", "", "dir")
                if dir ~= "" then
                    builtin.find_files({ search_dirs = { dir } })
                end
            end, { desc = "Find files in dir" })
            vim.keymap.set("n", "<leader>fG", function()
                local dir = vim.fn.input("Grep in: ", "", "dir")
                if dir ~= "" then
                    builtin.live_grep({ search_dirs = { dir } })
                end
            end, { desc = "Live grep in dir" })
            vim.keymap.set("n", "<leader>fb", builtin.buffers, { desc = "Buffers" })
            vim.keymap.set("n", "<leader>fh", builtin.help_tags, { desc = "Help tags" })
            vim.keymap.set("n", "<leader>fk", builtin.keymaps, { desc = "Keymaps" })
            vim.keymap.set("n", "<leader>fd", builtin.diagnostics, { desc = "Diagnostics" })
            vim.keymap.set("n", "<leader>fs", builtin.lsp_document_symbols, { desc = "Document symbols" })
            vim.keymap.set("n", "<leader>fr", builtin.resume, { desc = "Resume last picker" })
            -- LSP
            vim.keymap.set("n", "gr", builtin.lsp_references, { desc = "LSP references" })
            vim.keymap.set("n", "gd", builtin.lsp_definitions, { desc = "LSP definitions" })
            vim.keymap.set("n", "gi", builtin.lsp_implementations, { desc = "LSP implementations" })
            -- Git
            vim.keymap.set("n", "<leader>gl", builtin.git_commits, { desc = "Git commits" })
            vim.keymap.set("n", "<leader>gs", builtin.git_status, { desc = "Git status" })
            vim.keymap.set("n", "<leader>gb", builtin.git_branches, { desc = "Git branches" })
        end,
    },
}
