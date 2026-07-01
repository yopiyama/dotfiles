return {
  "stevearc/conform.nvim",
  event = { "BufWritePre" },
  cmd = { "ConformInfo" },
  opts = {
    formatters_by_ft = {
      lua = { "stylua" },
      python = { "ruff_format" },
      go = { "goimports", "gofmt" },
      sh = { "shfmt" },
      json = { "jq" },
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

      return {
        timeout_ms = 500,
        lsp_fallback = true,
      }
    end,
  },
}
