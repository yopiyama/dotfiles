#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Get Battery Wattage
# @raycast.mode fullOutput

# Optional parameters:
# @raycast.icon 🤖

# Documentation:
# @raycast.author yopiyama

system_profiler SPPowerDataType | awk '
/^[[:space:]]+AC Charger Information:/{f=1; next}
f && /^[[:space:]]+[A-Za-z].*:[[:space:]]*$/{ exit }
f{
  sub(/^[[:space:]]+/, "", $0)
  if($0 ~ /^(Family|ID):/) next
  print
}
'
