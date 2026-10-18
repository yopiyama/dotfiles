return {
    {
        "folke/noice.nvim",
        event = "VeryLazy",
        dependencies = {
            "MunifTanjim/nui.nvim",
            "rcarriga/nvim-notify",
        },
        opts = {
            -- : の入力欄と補完候補だけを浮動 UI にする。
            cmdline = {
                enabled = true,
                view = "cmdline_popup",
            },
            popupmenu = {
                enabled = true,
                backend = "nui",
            },

            -- コマンドの結果・通知は右上へ。LSP UI は既存の表示を維持する。
            messages = {
                enabled = true,
                view = "notify",
                view_error = "notify",
                view_warn = "notify",
            },
            notify = { enabled = true, view = "notify" },
            lsp = {
                progress = { enabled = false },
                hover = { enabled = false },
                signature = { enabled = false },
                message = { enabled = false },
            },

            -- :!pwd など、Ex コマンドから起動した外部コマンドの出力も右上へ出す。
            -- Noice の標準メッセージ route ではこの種の出力が対象外になる。
            routes = {
                {
                    view = "notify",
                    filter = { event = "msg_show", cmdline = "^:!" },
                    opts = { title = "Shell", replace = true, merge = true },
                },
            },

            presets = {
                -- / と ? の検索入力も cmdline_popup（画面中央）で表示する。
                bottom_search = false,
                -- command_palette は入力欄を画面上部に配置するため使わない。
                -- cmdline_popup の既定位置（画面中央）を使う。
                command_palette = false,
                long_message_to_split = false,
                inc_rename = false,
                lsp_doc_border = false,
            },
        },
    },
}
