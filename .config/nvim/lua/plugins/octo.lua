return {
    "pwntester/octo.nvim",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-telescope/telescope.nvim",
        "nvim-tree/nvim-web-devicons",
        -- PR レビューの差分表示に diffview を使う
        "sindrets/diffview.nvim",
    },
    -- `gh` CLI が認証済みであることが前提 (gh auth login)
    cmd = { "Octo", "OctoPRCurrent" },
    keys = {
        { "<leader>oc", "<cmd>OctoPRCurrent<CR>", desc = "Octo: current branch PR" }
        { "<leader>op", "<cmd>Octo pr list<CR>", desc = "Octo: PR list" },
        { "<leader>oP", "<cmd>Octo pr create<CR>", desc = "Octo: PR create" },
        { "<leader>oi", "<cmd>Octo issue list<CR>", desc = "Octo: issue list" },
        { "<leader>oI", "<cmd>Octo issue create<CR>", desc = "Octo: issue create" },
        { "<leader>or", "<cmd>Octo review start<CR>", desc = "Octo: review start" },
        { "<leader>os", "<cmd>Octo review submit<CR>", desc = "Octo: review submit" },
        { "<leader>oo", "<cmd>Octo<CR>", desc = "Octo: command palette" },
    },
    config = function()
        vim.api.nvim_create_user_command("OctoPRCurrent", function()
            local pr_number = vim.trim(vim.fn.system("gh pr view --json number -q .number 2>/dev/null"))
            if pr_number ~= "" then
                vim.cmd("Octo pr edit " .. pr_number)
            else
                vim.notify("No PR found for current branch", vim.log.levels.WARN)
            end
        end, {})
        require("octo").setup({
            -- telescope を picker として使う (既存設定を流用)
            picker = "telescope",
            -- PR レビューを diffview レイアウトで表示
            ui = {
                use_signcolumn = true,
            },
        })
    end,
}
