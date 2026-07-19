return {
    "MeanderingProgrammer/render-markdown.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    ft = { "markdown", "octo" },
    opts = {
        file_types = { "markdown", "octo" },
    },
    init = function()
        -- octo バッファに markdown の treesitter ハイライトを適用
        vim.treesitter.language.register("markdown", "octo")
    end,
}
