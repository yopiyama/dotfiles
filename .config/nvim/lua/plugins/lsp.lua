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
        ensure_installed = { "lua_ls", "gopls", "pyright", "ts_ls", "yamlls", "marksman" },
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
        root_markers = { ".luarc.json", ".luarc.jsonc", ".luacheckrc", ".stylua.toml", "stylua.toml" },
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

      vim.lsp.config("ts_ls", {
        capabilities = capabilities,
      })

      vim.lsp.config("yamlls", {
        capabilities = capabilities,
        settings = {
          yaml = {
            -- GitHub Actions のワークフローに補完/検証スキーマを効かせる
            schemas = {
              ["https://json.schemastore.org/github-workflow.json"] = "/.github/workflows/*.{yml,yaml}",
            },
          },
        },
      })

      vim.lsp.config("marksman", {
        capabilities = capabilities,
      })

      -- diffview:// など file:// 以外のスキームのバッファでは LSP を起動させない
      -- （gopls 等が "DocumentURI scheme is not 'file'" エラーを返すのを防ぐ）
      -- LspAttach で detach すると didOpen 送信後になり手遅れなので、
      -- vim.lsp.start 自体をラップしてブロックする。
      local orig_lsp_start = vim.lsp.start
      vim.lsp.start = function(config, opts)
          opts = opts or {}
          local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
          local bufname = vim.api.nvim_buf_get_name(bufnr)
          if bufname:match("^%w+://") and not bufname:match("^file://") then
            return nil
          end
          return orig_lsp_start(config, opts)
      end

      -- Enable servers
      vim.lsp.enable({ "lua_ls", "gopls", "pyright", "ts_ls", "yamlls", "marksman" })
    end,
  },
}
