return {
    {
        "nvim-treesitter/nvim-treesitter",
        branch = "main",
        lazy = false,
        build = ":TSUpdate",
        -- main ブランチでは setup() が install_dir しか見ず、master の
        -- opts.ensure_installed / highlight.enable は存在しない。
        -- パーサの導入は install()、ハイライトの有効化は vim.treesitter.start() を明示的に呼ぶ。
        config = function()
            require("nvim-treesitter").install({
                "lua", "go", "python", "typescript", "tsx", "javascript",
                "json", "yaml", "toml", "bash", "markdown", "markdown_inline",
                "terraform", "hcl",
            })
            vim.api.nvim_create_autocmd("FileType", {
                callback = function(ev)
                    -- パーサ未導入の filetype では start() が error を投げるので握り潰す
                    pcall(vim.treesitter.start, ev.buf)
                end,
            })
        end,
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
