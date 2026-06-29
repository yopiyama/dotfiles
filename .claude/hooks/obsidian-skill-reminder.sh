#!/usr/bin/env bash
# UserPromptSubmit hook: ユーザー発話に Obsidian 関連の語が含まれていたら、
# connect-obsidian スキル（obsidian CLI） の使用を促すコンテキストを注入する。
set -euo pipefail

prompt="$(jq -r '.prompt // ""')"

if printf '%s' "$prompt" | grep -qiE 'obsidian|vault|デイリーノート|daily ?note'; then
    jq -n '{
        hookSpecificOutput: {
            hookEventName: "UserPromptSubmit",
            additionalContext: "ユーザー発話に Obsidian 関連の語が含まれています。Obsidian vault の読み書き・検索・open・テンプレート実行は、素の Read/Grep ではなく connect-obsidian スキル（obsidian CLI）を使って行ってください。"
        }
    }'
fi
