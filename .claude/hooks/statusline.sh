#!/usr/bin/env bash
# Claude Code statusLine: model name, context usage, session cost.
# Nerd Font icons + powerline-style separators, dimmed ANSI colors
# (tuned for terminals running powerlevel10k with Nerd Fonts).
set -euo pipefail

input="$(cat)"

model_name="$(jq -r '.model.display_name // "unknown"' <<<"$input")"
used_pct_raw="$(jq -r '.context_window.used_percentage // empty' <<<"$input")"
cost_usd="$(jq -r '.cost.total_cost_usd // empty' <<<"$input")"

# ---- Nerd Font glyphs ----
ICON_MODEL=""   # nf-fa-microchip
ICON_CTX=""     # nf-fa-dashboard
ICON_COST=""    # nf-fa-money
SEP_R=""        # powerline thin angle right

# ---- colors (dim-friendly, 256-color) ----
RESET=$'\033[0m'
DIM=$'\033[2m'
FG_MODEL=$'\033[38;5;110m'   # soft blue
FG_CTX_OK=$'\033[38;5;108m'  # soft green
FG_CTX_WARN=$'\033[38;5;179m' # soft yellow
FG_CTX_HOT=$'\033[38;5;167m' # soft red
FG_COST=$'\033[38;5;144m'    # soft tan
SEP_COLOR=$'\033[2;38;5;240m'  # dim dark grey separator
SEP=" ${SEP_COLOR}${SEP_R}${RESET} "

# ---- model segment ----
model_segment="${FG_MODEL}${ICON_MODEL} ${model_name}${RESET}"

# ---- context segment ----
if [[ -n "$used_pct_raw" && "$used_pct_raw" != "null" ]]; then
  used_pct="$(printf '%.0f' "$used_pct_raw")"
  if (( used_pct >= 90 )); then
    ctx_color="$FG_CTX_HOT"
  elif (( used_pct >= 70 )); then
    ctx_color="$FG_CTX_WARN"
  else
    ctx_color="$FG_CTX_OK"
  fi
  context_segment="${ctx_color}${ICON_CTX} ${used_pct}%${RESET}"
else
  context_segment="${DIM}${ICON_CTX} --${RESET}"
fi

# ---- cost segment ----
if [[ -n "$cost_usd" && "$cost_usd" != "null" ]]; then
  cost_fmt="$(printf '%.2f' "$cost_usd")"
  cost_segment="${FG_COST}${ICON_COST} \$${cost_fmt}${RESET}"
else
  cost_segment="${DIM}${ICON_COST} --${RESET}"
fi

printf "%b" "${model_segment}${SEP}${context_segment}${SEP}${cost_segment}\n"
