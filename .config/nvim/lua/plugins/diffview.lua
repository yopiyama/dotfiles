return {
    "sindrets/diffview.nvim",
    -- octo.nvim の PR レビュー時の差分表示にも使われる
    dependencies = { "nvim-lua/plenary.nvim" },
    cmd = {
        "DiffviewOpen",
        "DiffviewClose",
        "DiffviewToggle",
        "DiffviewFileHistory",
        "DiffviewFocusFiles",
        "DiffviewRefresh",
    },
    keys = {
        { "<leader>gd", "<cmd>DiffviewOpen<CR>", desc = "Diffview: open (working tree)" },
        { "<leader>gc", "<cmd>DiffviewClose<CR>", desc = "Diffview: close" },
        -- 現在のファイルのコミット履歴
        { "<leader>gh", "<cmd>DiffviewFileHistory %<CR>", desc = "Diffview: file history (current)" },
        -- リポジトリ全体の履歴
        { "<leader>gH", "<cmd>DiffviewFileHistory<CR>", desc = "Diffview: file history (repo)" },
    },
    config = function()
        require("diffview").setup({
            enhanced_diff_hl = true,
            view = {
                -- マージコンフリクト解決用の 3-way merge ツール
                merge_tool = {
                    layout = "diff3_mixed",
                    disable_diagnostics = true,
                },
            },
            keymaps = {
                view = {
                    { "n", "q", "<cmd>DiffviewClose<CR>", { desc = "Close diffview" } },
                },
                file_panel = {
                    { "n", "q", "<cmd>DiffviewClose<CR>", { desc = "Close diffview" } },
                },
                file_history_panel = {
                    { "n", "q", "<cmd>DiffviewClose<CR>", { desc = "Close diffview" } },
                },
            },
        })
    end,
}
