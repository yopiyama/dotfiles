return {
    "kdheepak/lazygit.nvim",
    lazy = true,
    cmd = { "LazyGit" },
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
        { "<leader>gg", "<cmd>LazyGit<CR>", desc = "LazyGit" }
    },
}
