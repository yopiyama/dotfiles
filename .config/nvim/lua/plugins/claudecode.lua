-- Claude Code との IDE 連携 (VSCode / JetBrains 拡張と同じ MCP WebSocket を喋る)
-- 別ターミナル (iTerm2 ペイン等) で起動した `claude` から /ide で接続可能。
return {
    "coder/claudecode.nvim",
    -- snacks.nvim はターミナル統合用 (README 推奨)
    dependencies = { "folke/snacks.nvim" },
    config = true,
    -- cmd を列挙しておくと lazy.nvim がコマンドスタブを作るので、
    -- キーマップを押す前でも `:ClaudeCode` 等が解決できる。
    cmd = {
        "ClaudeCode",
        "ClaudeCodeFocus",
        "ClaudeCodeSelectModel",
        "ClaudeCodeAdd",
        "ClaudeCodeSend",
        "ClaudeCodeTreeAdd",
        "ClaudeCodeStatus",
        "ClaudeCodeStart",
        "ClaudeCodeStop",
        "ClaudeCodeOpen",
        "ClaudeCodeClose",
        "ClaudeCodeDiffAccept",
        "ClaudeCodeDiffDeny",
        "ClaudeCodeCloseAllDiffs",
    },
    keys = {
        { "<leader>a", nil, desc = "AI / Claude Code" },
        { "<leader>ac", "<cmd>ClaudeCode<cr>", desc = "Claude: toggle" },
        { "<leader>af", "<cmd>ClaudeCodeFocus<cr>", desc = "Claude: focus" },
        { "<leader>ar", "<cmd>ClaudeCode --resume<cr>", desc = "Claude: resume" },
        { "<leader>aC", "<cmd>ClaudeCode --continue<cr>", desc = "Claude: continue" },
        { "<leader>am", "<cmd>ClaudeCodeSelectModel<cr>", desc = "Claude: select model" },
        { "<leader>ab", "<cmd>ClaudeCodeAdd %<cr>", desc = "Claude: add current buffer" },
        { "<leader>as", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Claude: send selection" },
        -- ファイラ上で押した場合は対象ファイルを @ コンテキストとして送る
        {
            "<leader>as",
            "<cmd>ClaudeCodeTreeAdd<cr>",
            desc = "Claude: add file from tree",
            ft = { "neo-tree", "NvimTree", "oil", "minifiles", "netrw", "snacks_picker_list" },
        },
        -- 差分レビュー (Claude が提示した編集を承認 / 却下)
        { "<leader>aa", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Claude: accept diff" },
        { "<leader>ad", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "Claude: deny diff" },
    },
}
