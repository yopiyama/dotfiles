return {
  {
    "windwp/nvim-autopairs",
    lazy = false,
    config = function()
      require("nvim-autopairs").setup({
        -- Keep it simple and always on; avoids timing issues with lazy loading
        check_ts = false,
      })

      -- Integrate with nvim-cmp if available (auto-insert closing after completion)
      local ok_cmp, cmp = pcall(require, "cmp")
      if ok_cmp then
        local cmp_autopairs = require("nvim-autopairs.completion.cmp")
        cmp.event:on("confirm_done", cmp_autopairs.on_confirm_done())
      end
    end,
  },
}
