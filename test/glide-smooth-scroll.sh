#!/usr/bin/env bash
set -euo pipefail

# Manual rendering regression fixture: run inside a Ghostty Glide terminal.
# The header and footer must remain still while the alternate-screen region
# glides within its top/bottom margins. This cannot verify graphics headlessly.
if [[ ! -t 1 ]]; then
  printf 'Run this test in an interactive terminal.\n' >&2
  exit 1
fi

read -r rows cols < <(stty size)
if (( rows < 12 || cols < 30 )); then
  printf 'Terminal must be at least 12 rows x 30 columns.\n' >&2
  exit 1
fi

bottom=$((rows - 2))
cleanup() {
  printf '\033[r\033[?25h\033[?1049l'
}
trap cleanup EXIT INT TERM

line() {
  local r=$1 message=$2
  printf '\033[%d;1H\033[2K%.*s' "$r" "$cols" "$message"
}

printf '\033[?1049h\033[?25l\033[2J'
line 1 'Ghostty Glide | alternate-screen scroll-region visual check'
line 2 'TOP BORDER: must stay fixed'
line "$((rows - 1))" 'BOTTOM BORDER: must stay fixed'
line "$rows" 'Observe clipping, ghost rows, cursor, and smooth deceleration.'

printf '\033[3;%dr' "$bottom"
for ((i=3; i<=bottom; i++)); do
  line "$i" "Initial region row $i"
done
sleep 1

for ((i=1; i<=28; i++)); do
  printf '\033[1S'
  line "$bottom" "SU upward scroll $i"
  sleep 0.04
done
for ((i=1; i<=20; i++)); do
  printf '\033[1T'
  line 3 "SD downward scroll $i"
  sleep 0.04
done

# IND at the bottom margin is another supported alternate-screen scroll.
for ((i=1; i<=12; i++)); do
  printf '\033[%d;1H\033D' "$bottom"
  line "$bottom" "IND downward index $i"
  sleep 0.04
done
sleep 2
