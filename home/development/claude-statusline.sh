#!/usr/bin/env bash
# Claude Code の statusLine フック。stdin に 1 回の呼び出しごとの JSON が流れ、
# 標準出力の 1 行目だけが画面下部に表示される。
# 入力スキーマ: https://code.claude.com/docs/en/statusline
#
# rate_limits.{five_hour,seven_day} はデータが無い間キーごと欠落し、
# used_percentage だけあって resets_at が無いこともある。欠落は -1 に潰し、
# used_percentage が無ければセグメントごと、resets_at が無ければ残り時間だけ落とす。
#
# 数値の型検証は jq 側に寄せ、bash に渡る時点で整数を保証する。フィールド区切りは
# US (\x1f): タブは IFS 空白文字なので空フィールドで列がずれる。

input=$(cat)

int_or_missing='if type == "number" then floor else -1 end'

fields=$(jq -r --arg us $'\x1f' "[
  (.model.display_name // \"\" | if . == \"\" then \"?\" else . end),
  (.context_window.used_percentage      // 0  | if type == \"number\" then floor else 0 end),
  (.rate_limits.five_hour.used_percentage // -1 | $int_or_missing),
  (.rate_limits.five_hour.resets_at       // -1 | $int_or_missing),
  (.rate_limits.seven_day.used_percentage // -1 | $int_or_missing),
  (.rate_limits.seven_day.resets_at       // -1 | $int_or_missing)
] | map(tostring) | join(\$us)" <<<"$input" 2>/dev/null)

if [ -z "$fields" ]; then
  echo "🤖 ?"
  exit 0
fi

IFS=$'\x1f' read -r model ctx five_pct five_reset week_pct week_reset <<<"$fields"

reset=$'\033[0m'
dim=$'\033[2m'
bold=$'\033[1m'

heat() {
  if [ "$1" -ge 90 ]; then
    printf '%s' $'\033[1;31m'
  elif [ "$1" -ge 70 ]; then
    printf '%s' $'\033[33m'
  else
    printf '%s' $'\033[32m'
  fi
}

# resets_at は unix 秒
countdown() {
  local secs=$(( $1 - $(date +%s) ))
  [ "$secs" -lt 0 ] && secs=0
  local h=$(( secs / 3600 )) m=$(( secs % 3600 / 60 ))
  if [ "$h" -ge 24 ]; then
    printf '%dd%dh' $(( h / 24 )) $(( h % 24 ))
  elif [ "$h" -gt 0 ]; then
    printf '%dh%dm' "$h" "$m"
  else
    printf '%dm' "$m"
  fi
}

segments=(
  "🤖 ${bold}${model}${reset}"
  "🧠 $(heat "$ctx")${ctx}%${reset}"
)

limit_segment() {
  local icon=$1 label=$2 pct=$3 rts=$4
  local out
  out="$icon ${dim}${label}${reset} $(heat "$pct")${pct}%${reset}"
  [ "$rts" -ge 0 ] && out+=" ${dim}↻$(countdown "$rts")${reset}"
  printf '%s' "$out"
}

[ "$five_pct" -ge 0 ] && segments+=( "$(limit_segment "⏳" 5h "$five_pct" "$five_reset")" )
[ "$week_pct" -ge 0 ] && segments+=( "$(limit_segment "📅" 1w "$week_pct" "$week_reset")" )

sep="${dim} │ ${reset}"
out=""
for s in "${segments[@]}"; do
  [ -n "$out" ] && out+="$sep"
  out+="$s"
done
printf '%s\n' "$out"
