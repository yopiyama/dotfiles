return {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
        -- プレフィックスにグループ名を付けると一覧が見やすくなる
        spec = {
            { "<leader>f", group = "find" },
            { "<leader>g", group = "git / diffview" },
            { "<leader>o", group = "octo (GitHub)" },
            { "<leader>r", group = "rename" },
            { "<leader>c", group = "code action" },
        },
    },
    keys = {
        {
            "<leader>?",
            function()
                require("which-key").show({ global = true })
            end,
            desc = "Which-key: 全キーマップ",
        },
    },
}
