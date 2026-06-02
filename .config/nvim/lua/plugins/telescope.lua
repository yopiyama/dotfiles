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
            telescope.setup({
                defaults = {
                    mappings = {
                        i = {
                            ["<C-j>"] = "move_selection_next",
                            ["<C-k>"] = "move_selection_previous",
                        },
                    },
                },
            })
            pcall(telescope.load_extension, "fzf")

            local builtin = require("telescope.builtin")
            vim.keymap.set("n", "<leader>ff", buildin.find_files, { desc = "Find files" })
            vim.keymap.set("n", "<leader>fg", buildin.live_grep, { desc = "Live grep" })
            vim.keymap.set("n", "<leader>fb", buildin.buffers, { desc = "Buffers" })
            vim.keymap.set("n", "<leader>fh", buildin.help_tags, { desc = "Help tags" })
        end,
    },
}
