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

-- フォーカス中のウィンドウを見分けやすくする
local focus_group = augroup("FocusedWindowHighlight", { clear = true })

local function apply_focus_highlights()
    -- 非アクティブウィンドウの背景を tokyonight moon の bg_dark で沈める
    vim.api.nvim_set_hl(0, "NormalNC", { bg = "#1e2030" })
end

autocmd({ "VimEnter", "ColorScheme" }, {
    group = focus_group,
    callback = apply_focus_highlights,
})

-- 全ウィンドウで cursorline が出ると見分けが付かないので、アクティブウィンドウのみ表示する
autocmd({ "WinEnter", "BufWinEnter" }, {
    group = focus_group,
    callback = function()
        vim.wo.cursorline = true
    end,
})

autocmd("WinLeave", {
    group = focus_group,
    callback = function()
        vim.wo.cursorline = false
    end,
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

-- NOTE: neo-tree を float 運用に移行したため、常駐サイドバー前提の以下 2 つの
-- autocmd は無効化中。サイドバー常駐に戻す場合はコメント解除する。
--
-- -- :q でファイルを閉じて neo-tree だけになったら、右にペインを復元
-- vim.api.nvim_create_autocmd("WinClosed", {
--     nested = true,
--     callback = function()
--         vim.schedule(function()
--             local wins = vim.api.nvim_list_wins()
--             -- フローティングウィンドウ（telescope 等）を除外して判定
--             local normal_wins = vim.tbl_filter(function(w)
--                 local cfg = vim.api.nvim_win_get_config(w)
--                 return not cfg.relative or cfg.relative == ""
--             end, wins)
--             if #normal_wins ~= 1 then
--                 return
--             end
--             local tree_win = normal_wins[1]
--             if vim.bo[vim.api.nvim_win_get_buf(tree_win)].filetype ~= "neo-tree" then
--                 return
--             end
--             -- listed バッファが残っていればそれを表示、なければ空バッファ
--             local listed = vim.tbl_filter(function(b)
--                 return vim.bo[b].buflisted
--             end, vim.api.nvim_list_bufs())
--             if #listed > 0 then
--                 vim.cmd("rightbelow vertical sbuffer " .. listed[1])
--             else
--                 vim.cmd("rightbelow vnew")
--             end
--             -- neo-tree のデフォルト幅 (40) に戻す
--             vim.api.nvim_win_set_width(tree_win, 40)
--             -- カーソルを neo-tree 側へ戻す
--             vim.api.nvim_set_current_win(tree_win)
--         end)
--     end,
-- })
--
-- -- neo-tree 上で :q / :wq したら nvim 全体を終了
-- vim.api.nvim_create_autocmd("FileType", {
--     pattern = "neo-tree",
--     callback = function()
--         vim.cmd("cnoreabbrev <buffer> q qa")
--         vim.cmd("cnoreabbrev <buffer> wq wqa")
--     end,
-- })

-- Insert mode を抜けたら ATOK を英字モードに強制的に戻す。
-- IME が「あ」のままだとノーマルモードのキー入力が仮名変換されて操作不能になるのを防ぐ。
-- ATOK は英字/かなを独立した入力ソースではなく単一ソース内のモードとして扱うため、
-- com.apple.keylayout.ABC ではなく ATOK 内の英字モード ID を指定する
-- (karabiner.nix の tmux leader キーの設定と同じ ID)。
local im_select = "/opt/homebrew/bin/im-select"
local ime_english = "com.justsystems.inputmethod.atok36.Roman"

if vim.fn.executable(im_select) == 1 then
    autocmd("InsertLeave", {
        group = augroup("ImeForceEnglish", { clear = true }),
        callback = function()
            -- im-select は 1 回あたり ~200ms かかるので必ず非同期で投げる
            vim.system({ im_select, ime_english })
        end,
    })
end

-- 日本語の「文」単位移動。) / ( を句点区切りにする。
--
-- 素の ) / ( が見る文末は ". " "! " "? " (ピリオド類 + 空白) に固定されており、
-- 設定で変えられない。句点で終わって空白を入れない日本語文では文末が一切見つからず、
-- 段落末や行末まで飛んでしまう。これが文単位でカーソルを動かせない原因。
--
-- 文字 (h/l) → 文節 (W/E/B, jasegment) → 文 (下の ) / () → 段落 (}/{) と粒度が揃う。
--
-- 全 filetype に入れるとコードの ) が壊れる (`foo.bar` のピリオドで止まる) ので、
-- 文章を書く filetype のバッファローカルに限定する。
local ja_sentence_group = augroup("JapaneseSentenceMotion", { clear = true })

-- 「次の文の先頭の非空白文字」を直接探す。
--   [。．！？] の後ろの閉じ括弧・閉じ引用符は文末側に含める (「〜です。」→ 」の後に飛ぶ)
--   ASCII の . ! ? は後続の空白を必須にする (foo.bar やバージョン番号で止まらないように)
--   \_s を使い、句点が行末にある場合は改行を跨いで次行の先頭に着地する
local ja_sentence_pat = [=[\%([。．！？][」』）”’]*\|[.!?][)\]"']*\_s\)\_s*\zs\S]=]

local function ja_sentence_motion(backward)
    local flags = backward and "bW" or "W"
    for _ = 1, vim.v.count1 do
        if vim.fn.search(ja_sentence_pat, flags) == 0 then
            -- 文末が無ければバッファの端へ寄せる (素の ) / ( と同じ感覚)。
            -- gg / G だけだと 'startofline' 次第で元の桁が残るので明示的に行頭/行末を付ける
            vim.cmd("normal! " .. (backward and "gg^" or "G$"))
            break
        end
    end
end

autocmd("FileType", {
    group = ja_sentence_group,
    pattern = { "markdown", "text", "gitcommit", "octo" },
    callback = function(args)
        local opts = { buffer = args.buf }
        vim.keymap.set({ "n", "x", "o" }, ")", function()
            ja_sentence_motion(false)
        end, vim.tbl_extend("force", opts, { desc = "次の文の先頭へ (句点区切り)" }))
        vim.keymap.set({ "n", "x", "o" }, "(", function()
            ja_sentence_motion(true)
        end, vim.tbl_extend("force", opts, { desc = "前の文の先頭へ (句点区切り)" }))
    end,
})

-- bufferline 対応: :q でバッファを閉じる
--   複数バッファ → 現バッファ削除、次のバッファへ
--   最後の1バッファ → [No Name] に置き換えてレイアウト維持
--   [No Name] のみ → Neovim 終了
local function smart_quit(bang)
    local bang_str = bang and "!" or ""

    -- コマンドラインウィンドウ (q: 等) では bprevious 系が E11 になるので素の quit
    if vim.fn.getcmdwintype() ~= "" then
        vim.cmd("quit" .. bang_str)
        return
    end

    -- floating window (neo-tree float 等) や特殊バッファ (help, quickfix 等) は
    -- バッファ整理をせずウィンドウを閉じるだけにする
    local win_cfg = vim.api.nvim_win_get_config(0)
    if (win_cfg.relative and win_cfg.relative ~= "") or vim.bo.buftype ~= "" then
        vim.cmd("quit" .. bang_str)
        return
    end

    local buf = vim.api.nvim_get_current_buf()

    -- 未保存のバッファは bdelete が E89 を投げるので、先に E37 相当で止める
    if vim.bo[buf].modified and not bang then
        vim.notify("E37: No write since last change (add ! to override)", vim.log.levels.ERROR)
        return
    end

    local listed = vim.tbl_filter(function(b)
        return vim.bo[b].buflisted
    end, vim.api.nvim_list_bufs())

    if #listed > 1 then
        vim.cmd("bprevious")
        vim.cmd("bdelete" .. bang_str .. " " .. buf)
        return
    end

    if vim.api.nvim_buf_get_name(buf) == "" then
        -- [No Name] からバッファのみ → 終了
        vim.cmd("qall" .. bang_str)
        return
    end

    -- 最後の実ファイルバッファ → 空バッファに差し替え
    vim.cmd("enew")
    vim.cmd("bdelete" .. bang_str .. " " .. buf)

    -- NOTE: サイドバー常駐時の挙動。float 運用中は不要なので無効化（戻す場合はコメント解除）
    -- -- neo-tree があればフォーカスを移す
    -- for _, win in ipairs(vim.api.nvim_list_wins()) do
    --     if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "neo-tree" then
    --         vim.api.nvim_set_current_win(win)
    --         break
    --     end
    -- end
end

vim.api.nvim_create_user_command("BufQ", function(opts)
    smart_quit(opts.bang)
end, { bang = true })

vim.api.nvim_create_user_command("BufWQ", function(opts)
    vim.cmd("write" .. (opts.bang and "!" or ""))
    smart_quit(false)
end, { bang = true })

-- :q → BufQ, :wq → BufWQ（コマンドモード先頭のみ展開、neo-tree はバッファローカル abbrev が優先）
vim.cmd([[cnoreabbrev <expr> q getcmdtype() == ':' && getcmdline() ==# 'q' ? 'BufQ' : 'q']])
vim.cmd([[cnoreabbrev <expr> wq getcmdtype() == ':' && getcmdline() ==# 'wq' ? 'BufWQ' : 'wq']])
