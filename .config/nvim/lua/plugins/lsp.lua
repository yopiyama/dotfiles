return {
  {
    "williamboman/mason.nvim",
    config = function()
      require("mason").setup()
    end,
  },
  {
    "williamboman/mason-lspconfig.nvim",
    dependencies = { "williamboman/mason.nvim" },
    config = function()
      require("mason-lspconfig").setup({
        -- よく使うのを例示（必要に応じて追加）
        ensure_installed = { "lua_ls", "gopls", "pyright" },
      })
    end,
  },
  {
    "neovim/nvim-lspconfig",
    dependencies = { "williamboman/mason-lspconfig.nvim" },
    config = function()
      -- Capabilities (enable completion integration when nvim-cmp is installed)
      local capabilities = vim.lsp.protocol.make_client_capabilities()
      local ok_cmp, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
      if ok_cmp then
        capabilities = cmp_nvim_lsp.default_capabilities(capabilities)
      end

      -- Nvim 0.11+ API: define/extend server configs via vim.lsp.config
      -- nvim-lspconfig provides base server definitions on runtimepath.
      vim.lsp.config("lua_ls", {
        capabilities = capabilities,
        settings = {
          Lua = {
            workspace = {
              library = {
                vim.env.VIMRUNTIME .. "/lua",
              },
            },
          },
        },
      })

      vim.lsp.config("gopls", {
        capabilities = capabilities,
      })

      vim.lsp.config("pyright", {
        capabilities = capabilities,
      })

      -- Enable servers
      vim.lsp.enable({ "lua_ls", "gopls", "pyright" })
    end,
  },
}
