local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd

autocmd("BufWritePre", {
	pattern = "*",
	command = ":%s/\\s\\+$//e",
})

local autoread_group = augroup("AutoRead", { clear = true })

autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
	group = autoread_group,
	pattern = "*",
	command = "checktime",
})

autocmd("FileChangedShellPost", {
	group = autoread_group,
	pattern = "*",
	callback = function()
		vim.notify("File changed on disk. Buffer reloaded.", vim.log.levels.INFO)
	end,
})

local whitespace_group = augroup("WhitespaceHighlight", { clear = true })

local function apply_whitespace_highlights()
	-- Make invisible characters clearly distinguishable from normal text.
	vim.api.nvim_set_hl(0, "Whitespace", { fg = "#5f5f5f" })
	vim.api.nvim_set_hl(0, "NonText", { fg = "#5f5f5f" })
	vim.api.nvim_set_hl(0, "SpecialKey", { fg = "#5f5f5f" })
	vim.api.nvim_set_hl(0, "EndOfBuffer", { fg = "#3a3a3a" })
end

autocmd({ "VimEnter", "ColorScheme" }, {
	group = whitespace_group,
	callback = apply_whitespace_highlights,
})
