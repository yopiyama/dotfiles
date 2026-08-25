#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title List Workona Spaces
# @raycast.mode fullOutput

# Optional parameters:
# @raycast.icon 🗂

# Documentation:
# @raycast.author yopiyama
# @raycast.description 開いている Workona space の id と名前を列挙する。
#   Switch Workona Space のドロップダウンを埋めるための補助。
#   workona.com/redirect/ (サスペンド済みタブ) と workona.com/inactive/ (tab cache) は除外する。

set -euo pipefail

osascript - <<'APPLESCRIPT'
on run
  set out to ""
  tell application "Google Chrome"
    set wn to count of windows
    repeat with wi from 1 to wn
      set w to window wi
      set tn to count of tabs of w
      -- workona.com/inactive を含むウィンドウは tab cache なので丸ごと飛ばす
      set isCache to false
      repeat with ti from 1 to tn
        if (URL of tab ti of w) starts with "https://workona.com/inactive" then set isCache to true
      end repeat
      if not isCache then
        repeat with ti from 1 to tn
          set u to URL of tab ti of w
          if u starts with "https://workona.com/0/" then
            set mark to ""
            if minimized of w then set mark to " [minimized]"
            set out to out & "win " & wi & mark & linefeed ¬
              & "  id    " & my spaceIdOf(u) & linefeed ¬
              & "  title " & (title of tab ti of w) & linefeed ¬
              & "  url   " & u & linefeed
          end if
        end repeat
      end if
    end repeat
  end tell
  if out is "" then return "Workona の space タブが見つかりません"
  return out
end run

-- https://workona.com/0/<id>/<slug>/ から <id> を取り出す
on spaceIdOf(u)
  set tailStr to text 23 thru -1 of u
  if tailStr is "" then return "(default)"
  set AppleScript's text item delimiters to "/"
  set parts to text items of tailStr
  set AppleScript's text item delimiters to ""
  if (count of parts) < 1 then return "(default)"
  return item 1 of parts
end spaceIdOf
APPLESCRIPT
