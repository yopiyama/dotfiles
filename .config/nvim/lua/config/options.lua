local options = {
	-- 文字系
	encoding = "utf-8",
	fileencoding = "utf-8",
	-- 表示系
	title = true,
	cmdheight = 2,
	termguicolors = true,
	pumheight = 10,
	showtabline = 2,
	background = "dark",
	winblend = 0,
	pumblend = 5,
	number=true,
	relativenumber = false,
	numberwidth = 4,
	signcolumn = "yes",
	list = true,
	listchars = {
		space = ".",
		tab = "--",
		eol = "~",
		extends = ">",
		precedes = "<",
		trail = "~",
	},
	-- 編集系
	expandtab = true,
	shiftwidth = 4,
	tabstop = 4,
	smartindent = true,
	wrap = true,
	cursorline = true,
	clipboard = "unnamedplus",
	completeopt = {"menuone","noselect"},
	-- 検索系
	hlsearch = true,
	ignorecase = true,
	smartcase = true,
	-- 操作系
	timeoutlen = 300,
	updatetime = 300,
	}

for k, v in pairs(options) do
	vim.opt[k] = v
end
