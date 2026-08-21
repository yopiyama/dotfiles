#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Switch Workona Space
# @raycast.mode compact

# Optional parameters:
# @raycast.icon 🗂
# @raycast.argument1 { "type": "text", "placeholder": "space id" }

# Documentation:
# @raycast.author yopiyama
# @raycast.description space id を直接指定して切り替える。常用は Open Workona Switcher の方で、
#   これは id が分かっている space への高速パス。id は List Workona Spaces で採取する。

set -euo pipefail

SPACE_ID="${1:-}"
if [ -z "$SPACE_ID" ]; then
  echo "space id が未指定。List Workona Spaces で採取できる" >&2
  exit 1
fi

# フォーカスを後回しにする待ち時間 (秒)。
# Workona 拡張は windows.onFocusChanged で 500ms デバウンスの最小化を予約するため、
# URL 書き換えを先に済ませ、デバウンスが空振りしてからフォーカスする。
FOCUS_DELAY="${WORKONA_FOCUS_DELAY:-0.7}"

osascript - "$SPACE_ID" "$FOCUS_DELAY" <<'APPLESCRIPT'
on run argv
  set spaceId to item 1 of argv
  set focusDelay to (item 2 of argv) as real
  set targetURL to "https://workona.com/0/" & spaceId

  set foundW to 0
  set foundT to 0

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
              if cand = 0 and u starts with "https://workona.com/0/" then set cand to ti
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

    -- lr() と同じことをする: pinned な Workona タブの URL を差し替える
    set URL of tab foundT of window foundW to targetURL
    set active tab index of window foundW to foundT
  end tell

  delay focusDelay

  tell application "Google Chrome"
    if minimized of window foundW then set minimized of window foundW to false
    set index of window foundW to 1
  end tell
  activate application "Google Chrome"

  return "switched"
end run
APPLESCRIPT
