-- :nt を :Neotree のエイリアスにする（引数も引き継ぐ）
vim.api.nvim_create_user_command("NT", function(opts)
  -- opts.args: "filesystem reveal" みたいな引数文字列
  vim.cmd("Neotree " .. opts.args)
end, { nargs = "*", complete = "command" })
