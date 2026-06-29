vim.api.nvim_create_user_command("DiffOrig", function()
  local filetype = vim.bo.filetype
  vim.cmd("vert new | set bt=nofile | r ++edit # | 0d_ | diffthis | wincmd p | diffthis")
  vim.cmd("wincmd p")
  vim.bo.filetype = filetype
  vim.cmd("wincmd p")
end, {})

-- :nt を :Neotree のエイリアスにする（引数も引き継ぐ）
vim.api.nvim_create_user_command("NT", function(opts)
  -- opts.args: "filesystem reveal" みたいな引数文字列
  vim.cmd("Neotree " .. opts.args)
end, { nargs = "*", complete = "command" })
