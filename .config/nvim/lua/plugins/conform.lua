return {
  "stevearc/conform.nvim",
  event = { "BufWritePre" },
  cmd = { "ConformInfo" },
  opts = {
    formatters_by_ft = {
      lua = { "stylua" },
      python = { "ruff_format" },
      -- goimports は gofmt 相当の整形 + import の追加/削除をまとめてやるので gofmt は不要
      go = { "goimports" },
      sh = { "shfmt" },
      json = { "jq" },
      yaml = { "prettier" },
      markdown = { "prettier" },
      javascript = { "prettier" },
      javascriptreact = { "prettier" },
      typescript = { "prettier" },
      typescriptreact = { "prettier" },
    },
    format_on_save = function(bufnr)
      -- 自動フォーマットを除外したいパスをここに追加 (Lua パターン)
      local exclude_patterns = {
        "sample%-path/",
      }

      local bufname = vim.api.nvim_buf_get_name(bufnr)
      for _, pattern in ipairs(exclude_patterns) do
        if bufname:match(pattern) then
          return nil
        end
      end

      -- goimports は未知の識別子を解決するときにモジュールキャッシュを探索するので、
      -- 依存の多いリポジトリでは 1s 前後かかる。500ms だと timeout して
      -- import が更新されないまま黙って保存される。
      local timeout_ms = 500
      if vim.bo[bufnr].filetype == "go" then
        timeout_ms = 3000
      end

      return {
        timeout_ms = timeout_ms,
        lsp_fallback = true,
      }
    end,
  },
}
