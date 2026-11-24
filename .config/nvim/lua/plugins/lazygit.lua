return {
    "kdheepak/lazygit.nvim",
    lazy = true,
    cmd = { "LazyGit" },
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
        -- Telescope 向けの TreesitterContext (zindex 60) より LazyGit を手前に出す。
        vim.api.nvim_create_autocmd("FileType", {
            group = vim.api.nvim_create_augroup("LazyGitWindow", { clear = true }),
            pattern = "lazygit",
            callback = function(args)
                local win = vim.api.nvim_get_current_win()
                if vim.api.nvim_win_get_buf(win) == args.buf
                    and vim.api.nvim_win_get_config(win).relative ~= ""
                then
                    -- 初回描画でウィンドウを配置してから重ね順を変える。
                    vim.cmd.redraw()
                    vim.api.nvim_win_set_config(win, { zindex = 70 })
                end
            end,
        })

        local edited_buffer
        local edited_window

        -- --remote-tab は通常のタブに開く。終了処理が起動元へ戻す前に、
        -- 開かれたバッファとウィンドウを覚えておく。
        vim.api.nvim_create_autocmd("BufEnter", {
            group = vim.api.nvim_create_augroup("LazyGitEdit", { clear = true }),
            callback = function(args)
                if vim.g.lazygit_opened == 1
                    and vim.bo[args.buf].buftype == ""
                then
                    edited_buffer = args.buf
                    edited_window = vim.api.nvim_get_current_win()
                end
            end,
        })

        -- lazygit.nvim が起動元へ戻った後、選択したファイルの画面へ移動する。
        vim.g.lazygit_on_exit_callback = function()
            local buf = edited_buffer
            local win = edited_window
            edited_buffer = nil
            edited_window = nil
            if buf and vim.api.nvim_buf_is_valid(buf) then
                if win and vim.api.nvim_win_is_valid(win)
                    and vim.api.nvim_win_get_buf(win) == buf
                then
                    vim.api.nvim_set_current_win(win)
                else
                    vim.api.nvim_set_current_buf(buf)
                end
            end
        end
    end,
    keys = {
        { "<leader>gg", "<cmd>LazyGit<CR>", desc = "LazyGit" }
    },
}
