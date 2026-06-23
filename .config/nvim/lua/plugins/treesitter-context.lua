return {
    {
        "nvim-treesitter/nvim-treesitter",
        build = ":TSUpdate",
        opts = {
            ensure_installed = { "lua", "go", "python", "typescript", "tsx", "javascript", "json", "yaml", "toml", "bash" },
        },
    },
    {
        "nvim-treesitter/nvim-treesitter-context",
        dependencies  = { "nvim-treesitter/nvim-treesitter" },
        config = function()
            require("treesitter-context").setup({
                max_lines = 5,
            })
        end,
    },
}
