-- Key bindings (global + LSP-related)

local M = {}

-- Set <leader> if not already set elsewhere
-- (If you already set mapleader in another file, you can remove this line.)
vim.g.mapleader = vim.g.mapleader or " "

-- Diagnostics (works even without an attached LSP)
vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, { desc = "Diagnostic: previous" })
vim.keymap.set("n", "]d", vim.diagnostic.goto_next, { desc = "Diagnostic: next" })
vim.keymap.set("n", "<leader>e", vim.diagnostic.open_float, { desc = "Diagnostic: open float" })

-- LSP buffer-local mappings (only active when LSP attaches)
local lsp_augroup = vim.api.nvim_create_augroup("UserLspKeymaps", { clear = true })

vim.api.nvim_create_autocmd("LspAttach", {
  group = lsp_augroup,
  callback = function(ev)
    local opts = { buffer = ev.buf }

    vim.keymap.set("n", "gd", vim.lsp.buf.definition, vim.tbl_extend("force", opts, { desc = "LSP: go to definition" }))
    vim.keymap.set("n", "gD", vim.lsp.buf.declaration, vim.tbl_extend("force", opts, { desc = "LSP: go to declaration" }))
    vim.keymap.set("n", "gr", vim.lsp.buf.references, vim.tbl_extend("force", opts, { desc = "LSP: references" }))
    vim.keymap.set("n", "gi", vim.lsp.buf.implementation, vim.tbl_extend("force", opts, { desc = "LSP: implementation" }))
    vim.keymap.set("n", "K", vim.lsp.buf.hover, vim.tbl_extend("force", opts, { desc = "LSP: hover" }))

    vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, vim.tbl_extend("force", opts, { desc = "LSP: rename" }))
    vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, vim.tbl_extend("force", opts, { desc = "LSP: code action" }))

    vim.keymap.set("n", "<leader>f", function()
      vim.lsp.buf.format({ async = true })
    end, vim.tbl_extend("force", opts, { desc = "LSP: format" }))
  end,
})

return M
