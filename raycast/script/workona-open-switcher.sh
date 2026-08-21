#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Open Workona Switcher
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🗂

# Documentation:
# @raycast.author yopiyama
# @raycast.description Workona の space switcher を開いた状態で Chrome を前面に出す。
#   「Chrome を復帰させてから Alt+A」を 1 アクションにまとめ、拡張の 500ms デバウンスを
#   避ける順序 (URL 書き換え → 待機 → フォーカス) を組み込んである。

set -euo pipefail

# Workona 拡張は windows.onFocusChanged で 500ms デバウンスの最小化を予約するため、
# URL 書き換えを先に済ませ、デバウンスが空振りしてからフォーカスする。
FOCUS_DELAY="${WORKONA_FOCUS_DELAY:-0.7}"

osascript - "$FOCUS_DELAY" <<'APPLESCRIPT'
on run argv
  set focusDelay to (item 1 of argv) as real
  set foundW to 0
  set foundT to 0
  set baseURL to ""

  tell application "Google Chrome"
    set wn to count of windows
    -- pass 1: 最小化されていないウィンドウを優先。pass 2 で最小化も許容する
    repeat with pass from 1 to 2
      if foundW = 0 then
        repeat with wi from 1 to wn
          set w to window wi
          if (pass = 2) or (not (minimized of w)) then
            -- workona.com/inactive を含むウィンドウは tab cache ("Hidden Tabs")。触らない
            set isCache to false
            set cand to 0
            set tn to count of tabs of w
            repeat with ti from 1 to tn
              set u to URL of tab ti of w
              if u starts with "https://workona.com/inactive" then set isCache to true
              if cand = 0 and u starts with "https://workona.com/0/" then
                set cand to ti
                set baseURL to u
              end if
            end repeat
            if (not isCache) and cand > 0 then
              set foundW to wi
              set foundT to cand
              exit repeat
            end if
          end if
        end repeat
      end if
    end repeat

    if foundW = 0 then error "Workona のタブを持つウィンドウが見つかりません"

    -- 既存のクエリ/フラグメントを落として action=switcher を付け直す
    set AppleScript's text item delimiters to "?"
    set baseURL to item 1 of text items of baseURL
    set AppleScript's text item delimiters to "#"
    set baseURL to item 1 of text items of baseURL
    set AppleScript's text item delimiters to ""

    set URL of tab foundT of window foundW to (baseURL & "?action=switcher")
    set active tab index of window foundW to foundT
  end tell

  delay focusDelay

  tell application "Google Chrome"
    if minimized of window foundW then set minimized of window foundW to false
    set index of window foundW to 1
  end tell
  activate application "Google Chrome"
end run
APPLESCRIPT
