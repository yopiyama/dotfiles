return {
    {
        "nvim-telescope/telescope.nvim",
        tag = "v0.2.2",
        dependencies = {
            "nvim-lua/plenary.nvim",
            { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
        },
        config = function()
            local telescope = require("telescope")
            local actions = require("telescope.actions")
            local action_state = require("telescope.actions.state")

            local function feed(keys)
                return function()
                    vim.api.nvim_feedkeys(
                        vim.api.nvim_replace_termcodes(keys, true, false, true),
                        "n",
                        false
                    )
                end
            end

            local ignore_patterns = {
                "%.git/",
                "node_modules/",
                "%.DS_Store",
            }

            telescope.setup({
                defaults = {
                    path_display = { "truncate" },
                    file_ignore_patterns = ignore_patterns,
                    vimgrep_arguments = {
                        "rg",
                        "--color=never",
                        "--no-heading",
                        "--with-filename",
                        "--line-number",
                        "--column",
                        "--smart-case",
                        "--hidden",
                        "--glob=!**/.git/*",
                    },
                    mappings = {
                        i = {
                            ["<C-j>"] = "move_selection_next",
                            ["<C-k>"] = "move_selection_previous",
                            ["<C-a>"] = feed("<Home>"),
                            ["<C-e>"] = feed("<End>"),
                            ["<C-b>"] = feed("<Left>"),
                            ["<C-f>"] = feed("<Right>"),
                            ["<C-d>"] = feed("<Del>"),
                        },
                    },
                },
                pickers = {
                    find_files = {
                        hidden = true,
                    },
                    lsp_reference = {
                        fname_width = 60
                    },
                    lsp_definitions = {
                        fname_width = 60
                    },
                    lsp_implementations = {
                        fname_width = 60
                    }
                },
            })
            pcall(telescope.load_extension, "fzf")

            local builtin = require("telescope.builtin")
            local sorters = require("telescope.sorters")

            -- find_files 用: 単語境界で一致するソーター
            local function get_word_sorter()
                return sorters.Sorter:new({
                    scoring_function = function(_, prompt, line)
                        if prompt == "" then return 1 end
                        local escaped = vim.pesc(prompt:lower())
                        if line:lower():find("%f[%w]" .. escaped .. "%f[%W]") then
                            return 0
                        end
                        return -1
                    end,
                    highlighter = function(_, prompt, display)
                        if prompt == "" then return {} end
                        local escaped = vim.pesc(prompt:lower())
                        local start = display:lower():find("%f[%w]" .. escaped .. "%f[%W]")
                        if not start then return {} end
                        local hl = {}
                        for i = start, start + #prompt - 1 do
                            table.insert(hl, i)
                        end
                        return hl
                    end,
                })
            end

            -- Picker wrapper:
            --   <C-s>  検索ディレクトリ変更
            --   <C-g>  除外パターン追加
            --   <C-w>  単語一致トグル
            --   <C-l>  固定文字列トグル
            local function open_with_scope(picker_fn, defaults, state)
                state = state or {}
                local search_dirs = state.search_dirs
                local excludes = state.excludes or {}
                local word_match = state.word_match or false
                local fixed_strings = state.fixed_strings or false
                local is_grep = (picker_fn == builtin.live_grep)

                local opts = vim.tbl_deep_extend("force", defaults or {}, {})
                if state.default_text then
                    opts.default_text = state.default_text
                end
                if search_dirs then
                    opts.search_dirs = search_dirs
                end

                if is_grep then
                    if word_match then
                        opts.word_match = "-w"
                    end
                    if fixed_strings then
                        opts.additional_args = function()
                            return { "--fixed-strings" }
                        end
                    end
                else
                    if word_match then
                        opts.sorter = get_word_sorter()
                    elseif fixed_strings then
                        opts.sorter = sorters.get_substr_matcher()
                    end
                end

                local info = {}
                if search_dirs then
                    for _, d in ipairs(search_dirs) do
                        table.insert(info, "in:" .. vim.fn.fnamemodify(d, ":~:."))
                    end
                end
                for _, ex in ipairs(excludes) do
                    table.insert(info, "-" .. ex)
                end
                if word_match then
                    table.insert(info, "[W]ord")
                end
                if fixed_strings then
                    table.insert(info, "[F]ixed")
                end
                if #info > 0 then
                    opts.prompt_title = table.concat(info, "  ")
                end

                if #excludes > 0 then
                    local patterns = vim.deepcopy(ignore_patterns)
                    vim.list_extend(patterns, excludes)
                    opts.file_ignore_patterns = patterns
                end

                local function reopen(pb, new_state)
                    local q = action_state.get_current_line()
                    actions.close(pb)
                    new_state.default_text = q
                    vim.schedule(function()
                        open_with_scope(picker_fn, defaults, new_state)
                    end)
                end

                opts.attach_mappings = function(_, map)
                    map("i", "<C-s>", function(pb)
                        local q = action_state.get_current_line()
                        actions.close(pb)
                        vim.schedule(function()
                            local dir = vim.fn.input("Search in: ", "", "dir")
                            if dir ~= "" then
                                open_with_scope(picker_fn, defaults, {
                                    search_dirs = { dir },
                                    excludes = excludes,
                                    default_text = q,
                                    word_match = word_match,
                                    fixed_strings = fixed_strings,
                                })
                            end
                        end)
                    end)
                    map("i", "<C-g>", function(pb)
                        local q = action_state.get_current_line()
                        actions.close(pb)
                        vim.schedule(function()
                            local pat = vim.fn.input("Exclude: ")
                            if pat ~= "" then
                                local new_ex = vim.deepcopy(excludes)
                                table.insert(new_ex, pat)
                                open_with_scope(picker_fn, defaults, {
                                    search_dirs = search_dirs,
                                    excludes = new_ex,
                                    default_text = q,
                                    word_match = word_match,
                                    fixed_strings = fixed_strings,
                                })
                            end
                        end)
                    end)
                    map("i", "<C-w>", function(pb)
                        reopen(pb, {
                            search_dirs = search_dirs,
                            excludes = excludes,
                            word_match = not word_match,
                            fixed_strings = fixed_strings,
                        })
                    end)
                    map("i", "<C-l>", function(pb)
                        reopen(pb, {
                            search_dirs = search_dirs,
                            excludes = excludes,
                            word_match = word_match,
                            fixed_strings = not fixed_strings,
                        })
                    end)
                    return true
                end

                picker_fn(opts)
            end

            -- Find
            vim.keymap.set("n", "<leader>ff", function()
                open_with_scope(builtin.find_files, {})
            end, { desc = "Find files" })
            vim.keymap.set("n", "<leader>fg", function()
                open_with_scope(builtin.live_grep, {})
            end, { desc = "Live grep" })
            vim.keymap.set("n", "<leader>fF", function()
                local dir = vim.fn.input("Find files in: ", "", "dir")
                if dir ~= "" then
                    open_with_scope(builtin.find_files, {}, { search_dirs = { dir } })
                end
            end, { desc = "Find files in dir" })
            vim.keymap.set("n", "<leader>fG", function()
                local dir = vim.fn.input("Grep in: ", "", "dir")
                if dir ~= "" then
                    open_with_scope(builtin.live_grep, {}, { search_dirs = { dir } })
                end
            end, { desc = "Live grep in dir" })
            vim.keymap.set("n", "<leader>fb", builtin.buffers, { desc = "Buffers" })
            vim.keymap.set("n", "<leader>fh", function()
                builtin.oldfiles({ cwd_only = true })
            end, { desc = "File history (oldfiles, cwd only)" })
            vim.keymap.set("n", "<leader>f?", builtin.help_tags, { desc = "Help tags" })
            vim.keymap.set("n", "<leader>fk", builtin.keymaps, { desc = "Keymaps" })
            vim.keymap.set("n", "<leader>fd", builtin.diagnostics, { desc = "Diagnostics" })
            vim.keymap.set("n", "<leader>fs", builtin.lsp_document_symbols, { desc = "Document symbols" })
            vim.keymap.set("n", "<leader>fr", builtin.resume, { desc = "Resume last picker" })
            -- LSP
            -- Neovim 0.11 標準の gr* マッピング (grr/gra/grn/gri/grt) を削除。
            -- これらが残っていると "gr" が prefix 扱いになり、timeoutlen 待ちや
            -- 素早い "grr" で標準動作 (quickfix) が暴発する。
            for _, lhs in ipairs({ "grr", "gra", "grn", "gri", "grt" }) do
                pcall(vim.keymap.del, "n", lhs)
            end
            vim.keymap.set("n", "gr", builtin.lsp_references, { desc = "LSP references" })
            vim.keymap.set("n", "gd", builtin.lsp_definitions, { desc = "LSP definitions" })
            vim.keymap.set("n", "gi", builtin.lsp_implementations, { desc = "LSP implementations" })
            -- Git
            vim.keymap.set("n", "<leader>gl", builtin.git_commits, { desc = "Git commits" })
            vim.keymap.set("n", "<leader>gs", builtin.git_status, { desc = "Git status" })
            vim.keymap.set("n", "<leader>gb", builtin.git_branches, { desc = "Git branches" })
        end,
    },
}
