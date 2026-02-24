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

-- Neo-tree の root が変わったら、そのパスに Nvim 全体の cwd を合わせる
vim.api.nvim_create_autocmd("User", {
  pattern = "NeoTreeRootChanged",
  callback = function(args)
    -- args.data.new_root は neo-tree が通知する新root（パス）
    local new_root = args.data and args.data.new_root
    if type(new_root) == "string" and new_root ~= "" then
      -- :! などの外部コマンドが Nvim 起動時の cwd に固定されるのを防ぐため全体を更新
      vim.cmd("cd " .. vim.fn.fnameescape(new_root))

      -- 既存/新規ウィンドウのローカル cwd が古いまま残るのを防ぐ
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local cfg = vim.api.nvim_win_get_config(win)
        if not cfg.relative or cfg.relative == "" then
          vim.api.nvim_win_call(win, function()
            vim.cmd("lcd " .. vim.fn.fnameescape(new_root))
          end)
        end
      end
    end
  end,
})

local function sync_cwd_to_neotree_root()
  local ok, manager = pcall(require, "neo-tree.sources.manager")
  if not ok then
    return
  end

  local state = manager.get_state("filesystem")
  local root = state and state.path
  if type(root) ~= "string" or root == "" then
    return
  end

  if vim.fn.getcwd() ~= root then
    vim.cmd("cd " .. vim.fn.fnameescape(root))
  end
  vim.cmd("lcd " .. vim.fn.fnameescape(root))
end

vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
  callback = function(args)
    if vim.bo[args.buf].buftype ~= "" then
      return
    end
    if vim.bo[args.buf].filetype == "neo-tree" then
      return
    end
    sync_cwd_to_neotree_root()
  end,
})
