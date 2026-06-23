-- Key bindings (global + LSP-related)

local M = {}

-- Set <leader> if not already set elsewhere
-- (If you already set mapleader in another file, you can remove this line.)
vim.g.mapleader = vim.g.mapleader or " "

-- Diagnostics (works even without an attached LSP)
vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, { desc = "Diagnostic: previous" })
vim.keymap.set("n", "]d", vim.diagnostic.goto_next, { desc = "Diagnostic: next" })
vim.keymap.set("n", "<leader>e", vim.diagnostic.open_float, { desc = "Diagnostic: open float" })
vim.keymap.set("n", "<Esc>", function()
  vim.cmd("nohlsearch")
  vim.lsp.buf.clear_references()
end, { desc = "Clear search + LSP highlights" })
vim.keymap.set("n", "<leader>q", "<cmd>cclose<CR>", { desc = "Close quickfix" })
vim.keymap.set("n", "<leader>l", "<cmd>lclose<CR>", { desc = "Close loclist" })

-- Copy current file's repo-relative path to clipboard
vim.keymap.set("n", "<leader><C-l>", function()
    local file = vim.fn.expand("%:p")
    if file == "" then
        vim.notify("No file in buffer", vim.log.levels.WARN)
        return
    end
    local result = vim.fn.systemlist({ "git", "-C", vim.fn.fnamemodify(file, ":h"), "ls-files", "--full-name", "--", file })
    local path = result[1]
    if vim.v.shell_error ~= 0 or not path or paht == "" then
        path = vim.fn.fnamemodify(file, ":.")
    end
    vim.fn.setreg("+", path)
    vim.notify("Copied: ", .. path)
end, { desc = "Cppy repo-relative file path" })

-- Fold (nvim-ufo)
vim.keymap.set("n", "zR", function() require("ufo").openAllFolds() end, { desc = "Fold: open all" })
vim.keymap.set("n", "zM", function() require("ufo").closeAllFolds() end, { desc = "Fold: close all" })
vim.keymap.set("n", "zK", function() require("ufo").peekFoldedLinesUnderCursor() end, { desc = "Fold: peek" })

-- Buffer navigation (bufferline)
vim.keymap.set("n", "<Tab>", "<cmd>BufferLineCycleNext<CR>", { desc = "Buffer: next" })
vim.keymap.set("n", "<S-Tab>", "<cmd>BufferLineCyclePrev<CR>", { desc = "Buffer: previous" })
vim.keymap.set("n", "<leader>x", "<cmd>bdelete<CR>", { desc = "Buffer: close" })

-- LSP buffer-local mappings (only active when LSP attaches)
local lsp_augroup = vim.api.nvim_create_augroup("UserLspKeymaps", { clear = true })

vim.api.nvim_create_autocmd("LspAttach", {
  group = lsp_augroup,
  callback = function(ev)
    local opts = { buffer = ev.buf }

    -- gd/gr/gi は telescope.lua 側で Telescope picker にバインド済み
    vim.keymap.set("n", "gD", vim.lsp.buf.declaration, vim.tbl_extend("force", opts, { desc = "LSP: go to declaration" }))
    vim.keymap.set("n", "K", vim.lsp.buf.hover, vim.tbl_extend("force", opts, { desc = "LSP: hover" }))

    vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, vim.tbl_extend("force", opts, { desc = "LSP: rename" }))
    vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, vim.tbl_extend("force", opts, { desc = "LSP: code action" }))

    vim.keymap.set("n", "<leader>f", function()
      vim.lsp.buf.format({ async = true })
    end, vim.tbl_extend("force", opts, { desc = "LSP: format" }))
  end,
})

return M
