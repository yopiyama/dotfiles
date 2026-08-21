-- 画面内の任意の位置へ英字ラベル 1〜2 打で飛ぶ (いわゆる easymotion 系)。
--
-- flash.nvim / leap.nvim のような「飛び先の文字を打つ」方式は日本語では使えない。
-- 「日」に飛ぶために IME を開いて変換し、またノーマルモードに戻す必要があり、
-- h/l を連打するより遅くなる (auto.lua の InsertLeave で ATOK を英字に戻している
-- 運用とも噛み合わない)。mini.jump2d は候補位置に英字ラベルを振る方式なので、
-- 飛び先が日本語でも IME に触らずに済む。
return {
  "echasnovski/mini.jump2d",
  -- mini.nvim は各モジュールの単体リポジトリにタグを打たないので main を追う
  version = false,
  dependencies = { "deton/jasegment.vim" },
  event = { "BufReadPost", "BufNewFile" },
  config = function()
    local jump2d = require("mini.jump2d")

    -- 既定の spotter は「空白区切りのかたまりの先頭/末尾」を候補にするため、空白の無い
    -- 日本語文では 1 行に 2 個しかラベルが立たず使えない (builtin_opts.word_start も
    -- `\k\+` 基準で、日本語は全部 keyword 文字なので同じ問題になる)。
    --
    -- jasegment の文節区切りをそのまま候補にすると、日本語は文節ごと・ASCII は
    -- 空白区切りの WORD ごとにラベルが立ち、どちらでも密度が妥当になる。
    -- SegmentCol は {col, colend, segment} のリストを 1-indexed のバイト位置で返す。
    local function segment_spotter(line_num, args)
      local ok, segs = pcall(vim.fn["jasegment#SegmentCol"], vim.g["jasegment#model"], line_num)
      if not ok or type(segs) ~= "table" then
        -- jasegment が読めていない場合は素の spotter に落とす
        return jump2d.default_spotter(line_num, args)
      end
      return vim.tbl_map(function(seg)
        return seg.col
      end, segs)
    end

    jump2d.setup({
      spotter = segment_spotter,
      -- ホームポジションに近い順。候補が 26 個を超えると 2 打目に繰り越される
      labels = "fjdkslaghrueiwoncmvbtyzpqx",
      view = {
        -- 候補のある行を沈めて、ラベルを拾いやすくする
        dim = true,
        -- 2 打必要なときに 2 打目のラベルも薄く見せる (先読みできて迷いが減る)
        n_steps_ahead = 1,
      },
      -- 既定の <CR> のまま。n / x / o の 3 モードに張られるので d<CR> や v<CR> も効く。
      -- quickfix と cmdline-window では mini.jump2d 側が <CR> を自動で元に戻す。
      mappings = { start_jumping = "<CR>" },
    })

    -- 行頭だけを候補にする版。段落単位でざっくり飛びたいときはラベルが少なくて速い
    vim.keymap.set({ "n", "x", "o" }, "<leader>j", function()
      jump2d.start(jump2d.builtin_opts.line_start)
    end, { desc = "Jump2d: 行頭へラベルジャンプ" })
  end,
}
