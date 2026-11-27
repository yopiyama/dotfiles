return {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
        -- キー入力中の候補を画面中央の浮動ウィンドウに表示する。
        preset = "modern",
        win = {
            -- row = 0.5 は、実際のウィンドウ高を除いた余白の中央に置く。
            -- カーソルとの重なりを避ける既定動作を無効にして、<leader> を
            -- 起点にした場合も下端へ移動させない。
            row = 0.5,
            no_overlap = false,
            width = { min = 40, max = 90 },
            height = { min = 4, max = 0.8 },
        },
        -- 1 列分の幅を確保し、候補を横に分割しない。
        layout = { width = { min = 0.9 } },
        -- g は Neovim 標準のプレフィックスなので自動トリガーだけでは拾えない。
        triggers = {
            { "<auto>", mode = "nxso" },
            { "g", mode = "n" },
        },
        -- 二打目の d が現在行を削除するのは、d のモーション待ちに限る。
        filter = function(mapping)
            if mapping.mode == "o" and mapping.lhs == "d" and mapping.desc == "Delete current line" then
                return vim.v.operator == "d"
            end
            return true
        end,
        -- プレフィックスにグループ名を付けると一覧が見やすくなる
        spec = {
            -- <leader>do と接頭辞を共有するため、サブメニューにも削除候補を出す。
            { "<leader>dd", desc = "Delete current line" },
            { "<leader>dw", desc = "Delete to next word" },
            { "d", mode = "o", desc = "Delete current line" },
            { "<leader>f", group = "find" },
            { "<leader>g", group = "git / diffview" },
            { "<leader>o", group = "octo (GitHub)" },
            { "<leader>r", group = "rename" },
            { "<leader>c", group = "code action" },
            { "<leader>s", group = "session" },
        },
    },
    keys = {
        {
            "<leader>m",
            function()
                require("which-key").show({ keys = "`", mode = "n" })
            end,
            desc = "Marks: select and jump",
        },
        {
            "<leader>?",
            function()
                require("which-key").show({ global = true })
            end,
            desc = "Which-key: 全キーマップ",
        },
    },
}
