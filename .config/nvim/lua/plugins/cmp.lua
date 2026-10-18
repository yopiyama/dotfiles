return {
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-cmdline",
      "hrsh7th/cmp-path",
      -- 関数呼び出し中に引数リスト（signature）を補完ウィンドウ内に表示する
      "hrsh7th/cmp-nvim-lsp-signature-help",
      -- 任意：スニペットも欲しいなら
      "L3MON4D3/LuaSnip",
      "saadparwaiz1/cmp_luasnip",
    },
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")

      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-Space>"] = cmp.mapping.complete(),      -- 補完を開く
          ["<C-e>"] = cmp.mapping.abort(),             -- 閉じる
          ["<CR>"] = cmp.mapping.confirm({ select = true }), -- 確定
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          -- 引数の途中でも signature を出したいので、最優先グループに入れる
          { name = "nvim_lsp_signature_help" },
          { name = "luasnip" },
        }),
      })

      -- :Mason のような Ex コマンドも、入力中に候補を絞り込む。
      -- 表示は noice.nvim の popupmenu に任せる。
      cmp.setup.cmdline(":", {
        mapping = cmp.mapping.preset.cmdline(),
        sources = cmp.config.sources({
          { name = "path" },
        }, {
          { name = "cmdline" },
        }),
        matching = { disallow_symbol_nonprefix_matching = false },
      })
    end,
  },
}
