-- picker 内のキー。どちらも telescope.lua の defaults.mappings.i を
-- この picker の中だけ上書きする (<C-a>=<Home>, <C-d>=<Del>)。
-- 気になる場合はここを <C-s> / <C-x> 等に変えれば済む。
local KEY_TOGGLE_SCOPE = "<C-a>"
local KEY_DELETE = "<C-d>"

-- persistence.nvim のセッションファイル名は cwd の区切りを "%"、
-- ブランチとの区切りを "%%" にエンコードしている (persistence/init.lua の M.current)。
-- main / master のセッションにはブランチ部が付かない。
local function parse_session(file, session_dir)
    local name = file:sub(#session_dir + 1, -5) -- ディレクトリ部と ".vim" を落とす
    local encoded_dir, encoded_branch = unpack(vim.split(name, "%%", { plain = true }))
    return {
        session = file,
        dir = (encoded_dir:gsub("%%", "/")),
        branch = encoded_branch and (encoded_branch:gsub("%%", "/")) or nil,
    }
end

-- mksession が吐くセッションファイルから、開いていたファイルを拾う。
--   badd +<行番号> <cd からの相対パス>  … バッファ一覧
--   edit <パス>                          … ウィンドウに表示されていたファイル
local function session_buffers(session_file)
    if vim.fn.filereadable(session_file) == 0 then
        return {}, {}
    end

    local files, shown = {}, {}
    for _, line in ipairs(vim.fn.readfile(session_file)) do
        local path = line:match("^badd %+%d+ (.+)$")
        if path then
            table.insert(files, (path:gsub("\\ ", " ")))
        end
        local edited = line:match("^edit (.+)$")
        if edited then
            shown[(edited:gsub("\\ ", " "))] = true
        end
    end
    return files, shown
end

-- displayer は右側を切るが、パスは末尾（プロジェクト名）の方が重要なので
-- 収まらないときは頭を "…" に潰して末尾を残す
local function shorten_path(path, width)
    if #path <= width then
        return path
    end
    return "…" .. path:sub(#path - width + 2)
end

local function relative_time(sec)
    local diff = os.time() - sec
    if diff < 60 then
        return "just now"
    elseif diff < 3600 then
        return string.format("%dm ago", math.floor(diff / 60))
    elseif diff < 86400 then
        return string.format("%dh ago", math.floor(diff / 3600))
    end
    return string.format("%dd ago", math.floor(diff / 86400))
end

-- 別プロジェクトのセッションに切り替えると前のバッファが残るので掃除する。
-- 未保存のバッファが 1 つでもあれば false を返して中断させる。
local function close_listed_buffers()
    local listed = vim.tbl_filter(function(b)
        return vim.bo[b].buflisted
    end, vim.api.nvim_list_bufs())

    for _, b in ipairs(listed) do
        if vim.bo[b].modified then
            return false
        end
    end
    for _, b in ipairs(listed) do
        pcall(vim.api.nvim_buf_delete, b, {})
    end
    return true
end

-- セッション復元後に残る、どのウィンドウにも出ていない空の [No Name] を落とす
-- (bufferline に幽霊タブとして出るため)
local function drop_empty_unnamed_buffers()
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
        local is_empty = vim.bo[b].buflisted
            and not vim.bo[b].modified
            and vim.api.nvim_buf_get_name(b) == ""
            and vim.api.nvim_buf_line_count(b) == 1
            and vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] == ""
            and vim.fn.win_findbuf(b)[1] == nil
        if is_empty then
            pcall(vim.api.nvim_buf_delete, b, {})
        end
    end
end

-- neo-tree に netrw を hijack させているので、`nvim <dir>` や neo-tree 経由の
-- 移動でディレクトリ名のバッファが湧く。これがセッションに焼き付くと、復元後に
-- bufferline から開こうとしたときにエラーになるので保存前後で落とす。
-- neo-tree 自身のバッファ (ft=neo-tree) も同様に対象外にする。
local function drop_neotree_buffers()
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
        local name = vim.api.nvim_buf_get_name(b)
        local is_neotree = vim.startswith(vim.bo[b].filetype, "neo-tree")
        local is_dir = name ~= "" and vim.fn.isdirectory(name) == 1
        if is_neotree or is_dir then
            pcall(vim.api.nvim_buf_delete, b, { force = true })
        end
    end
end

-- mksession は sessionoptions に関わらずアーグリストを `$argadd` として書き出し、
-- 復元時にそれが buflisted なディレクトリバッファになる。ディレクトリだけ間引く。
local function drop_directory_args()
    for i = vim.fn.argc() - 1, 0, -1 do
        if vim.fn.isdirectory(vim.fn.argv(i)) == 1 then
            pcall(vim.cmd, (i + 1) .. "argdelete")
        end
    end
end

local function load_session(item)
    if not close_listed_buffers() then
        vim.notify("未保存のバッファがあるためセッションを切り替えません", vim.log.levels.WARN)
        return
    end

    vim.fn.chdir(item.dir)

    -- auto.lua の sync_cwd_to_neotree_root が、切り替え後の BufEnter で
    -- 古い root に cwd を戻してしまうので neo-tree の state も追従させる
    local ok, manager = pcall(require, "neo-tree.sources.manager")
    if ok then
        local state = manager.get_state("filesystem")
        if state then
            state.path = item.dir
        end
    end

    -- persistence.load() は cwd と「現在の」ブランチからファイル名を引き直すため、
    -- 一覧で選んだブランチのセッションを開くには実ファイルを直接 source する
    vim.api.nvim_exec_autocmds("User", { pattern = "PersistenceLoadPre" })
    vim.cmd("silent! source " .. vim.fn.fnameescape(item.session))
    vim.api.nvim_exec_autocmds("User", { pattern = "PersistenceLoadPost" })

    drop_empty_unnamed_buffers()
end

local function session_picker()
    local persistence = require("persistence")
    local session_dir = require("persistence.config").options.dir
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    local entry_display = require("telescope.pickers.entry_display")
    local previewers = require("telescope.previewers")
    local uv = vim.uv or vim.loop

    -- 右ペインにそのセッションで開いていたファイル一覧を出す
    local previewer = previewers.new_buffer_previewer({
        title = "Buffers",
        -- セッションごとにプレビューバッファを使い回す
        get_buffer_by_name = function(_, entry)
            return entry.value.session
        end,
        define_preview = function(self, entry)
            local files, shown = session_buffers(entry.value.session)

            local lines = { vim.fn.fnamemodify(entry.value.dir, ":p:~") }
            if entry.value.branch then
                table.insert(lines, "branch: " .. entry.value.branch)
            end
            table.insert(lines, string.format("%d buffers", #files))
            table.insert(lines, "")

            if #files == 0 then
                table.insert(lines, "(バッファなし / セッションファイルが読めません)")
            end
            for _, f in ipairs(files) do
                -- ウィンドウに表示されていたファイルに印を付ける
                table.insert(lines, (shown[f] and "▸ " or "  ") .. f)
            end

            vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        end,
    })

    -- プレビューペインに半分持っていかれるので、結果ペインに収まる幅に抑える
    local dir_width = 34
    local displayer = entry_display.create({
        separator = "  ",
        items = { { width = dir_width }, { width = 20 }, { remaining = true } },
    })

    -- 既定は cwd 配下のみ。KEY_TOGGLE_SCOPE で全件表示に切り替える
    local cwd = vim.fn.getcwd()
    local scope_cwd = true

    local function in_cwd(dir)
        return dir == cwd or vim.startswith(dir, cwd .. "/")
    end

    -- 既定レイアウトの Border:change_title は no-op (telescope/pickers/layout.lua)
    -- なので、スコープの表示は prompt prefix 側で行う
    local function prompt_prefix()
        return scope_cwd and "cwd❯ " or "all❯ "
    end

    -- スコープ切り替えと削除のたびに作り直すのでクロージャにしておく
    local function make_finder()
        local items = {}
        for _, file in ipairs(persistence.list()) do
            local stat = uv.fs_stat(file)
            if stat then
                local item = parse_session(file, session_dir)
                if not scope_cwd or in_cwd(item.dir) then
                    item.mtime = stat.mtime.sec
                    table.insert(items, item)
                end
            end
        end

        return finders.new_table({
            results = items,
            entry_maker = function(item)
                local display_dir = vim.fn.fnamemodify(item.dir, ":p:~")
                return {
                    value = item,
                    ordinal = display_dir .. " " .. (item.branch or ""),
                    display = function()
                        return displayer({
                            shorten_path(display_dir, dir_width),
                            item.branch and ("(" .. item.branch .. ")") or "",
                            relative_time(item.mtime),
                        })
                    end,
                }
            end,
        })
    end

    pickers
        .new({}, {
            prompt_title = string.format(
                "Sessions in %s  (%s スコープ切替 / %s 削除)",
                vim.fn.fnamemodify(cwd, ":~"),
                KEY_TOGGLE_SCOPE,
                KEY_DELETE
            ),
            prompt_prefix = prompt_prefix(),
            finder = make_finder(),
            sorter = conf.generic_sorter({}),
            previewer = previewer,
            attach_mappings = function(prompt_bufnr, map)
                local function reload()
                    local picker = action_state.get_current_picker(prompt_bufnr)
                    picker:change_prompt_prefix(prompt_prefix(), "TelescopePromptPrefix")
                    picker:refresh(make_finder(), { reset_prompt = false })
                end

                actions.select_default:replace(function()
                    local entry = action_state.get_selected_entry()
                    actions.close(prompt_bufnr)
                    if entry then
                        vim.schedule(function()
                            load_session(entry.value)
                        end)
                    end
                end)

                map({ "i", "n" }, KEY_TOGGLE_SCOPE, function()
                    scope_cwd = not scope_cwd
                    reload()
                end)

                map({ "i", "n" }, KEY_DELETE, function()
                    local entry = action_state.get_selected_entry()
                    if not entry then
                        return
                    end
                    vim.fn.delete(entry.value.session)
                    vim.notify("セッションを削除: " .. vim.fn.fnamemodify(entry.value.dir, ":p:~"))
                    reload()
                end)

                return true
            end,
        })
        :find()
end

return {
    {
        "folke/persistence.nvim",
        -- BufReadPre で読み込む = 実ファイルを開いたときだけ自動保存が有効になる。
        -- 引数なし起動の自動復元は下の init 内の VimEnter から require で叩いて起こす。
        event = "BufReadPre",
        opts = {},
        init = function()
            local group = vim.api.nvim_create_augroup("PersistenceAutoRestore", { clear = true })

            -- `cmd | nvim -` のように stdin から読ませた場合は復元しない
            local from_stdin = false
            vim.api.nvim_create_autocmd("StdinReadPre", {
                group = group,
                callback = function()
                    from_stdin = true
                end,
            })

            -- 引数なしで起動したときだけ cwd のセッションを復元する。
            -- セッションファイルが無ければ load() は何もしない。
            vim.api.nvim_create_autocmd("VimEnter", {
                group = group,
                nested = true, -- 復元したバッファで BufRead 系 autocmd を発火させる
                callback = function()
                    if vim.fn.argc() > 0 or from_stdin then
                        return
                    end
                    require("persistence").load()
                end,
            })

            -- neo-tree は float 運用なので、開いたまま終了するとセッションに
            -- floating window が焼き付いて復元時にレイアウトが崩れる
            vim.api.nvim_create_autocmd("User", {
                group = group,
                pattern = "PersistenceSavePre",
                callback = function()
                    pcall(vim.cmd, "Neotree close")
                    drop_neotree_buffers()
                    drop_directory_args()
                end,
            })

            -- 既に neo-tree / ディレクトリを含んで保存されてしまったセッションが
            -- 残っているので、復元側でも落としておく
            vim.api.nvim_create_autocmd("User", {
                group = group,
                pattern = "PersistenceLoadPost",
                callback = function()
                    drop_neotree_buffers()
                    drop_directory_args()
                end,
            })
        end,
        keys = {
            {
                "<leader>ss",
                function()
                    require("persistence").load()
                end,
                desc = "Session: restore (cwd)",
            },
            {
                "<leader>sl",
                function()
                    require("persistence").load({ last = true })
                end,
                desc = "Session: restore last",
            },
            {
                "<leader>sf",
                session_picker,
                desc = "Session: find (telescope)",
            },
            {
                "<leader>sd",
                function()
                    require("persistence").stop()
                end,
                desc = "Session: don't save on exit",
            },
        },
    },
}
