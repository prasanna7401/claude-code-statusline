#!/usr/bin/env bash
# claude-code-statusline: a one- or two-line status line for Claude Code.
#
#   line 1: Opus 5.5 (1M)-high | my-project | main ±4 ↑1 | $0.52 ($9.87/h) | today $3.10 · Oct $41.20
#   line 2: ░░░░░░░░░░   7% 67.1k/1.0M | +142/-38 | ~12 turns to red | 5h █░░░░ 8% (19:40) · wk █░░░░ 1% (Thu)
#
# Parts (the names statusline.conf uses)
#   model     model name and effort level
#   folder    working directory name
#   git       branch with dirty / ahead / behind counts
#   cost      session cost and burn rate
#   spend     spend today and this month ("⚠ N unpriced" when Claude Code could
#             not price a model)
#   context   context-window bar, percentage, tokens used / window size
#   churn     lines Claude added/removed this session
#   forecast  how many turns remain before the context bar turns red
#   limits    plan usage limits (Pro/Max): percent of the 5-hour and weekly
#             limits used, with reset times
#
# Layout
#   $CLAUDE_CONFIG_DIR/statusline.conf (default ~/.claude/statusline.conf)
#   chooses which parts show, on which line, in what order. Without the file
#   the layout is:
#     line1=model folder git cost spend
#     line2=context churn forecast limits
#   A missing key keeps its default; "line2=" with nothing after it gives a
#   one-line status line. A part named on neither line is hidden, and its work
#   is skipped (no git call, no ledger or forecast file). Unknown names are
#   ignored, a part named twice shows only in its first place, and "#" starts
#   a comment. Each line joins its non-empty parts with a dim " | "; a line
#   with nothing to show is not printed.
#
# Install
#   See README.md, or run install.sh from the project folder.
#   By hand: copy this file to ~/.claude/statusline.sh and set
#     "statusLine": { "type": "command", "command": "bash ~/.claude/statusline.sh" }
#   in ~/.claude/settings.json (on Windows use C:/Users/<you>/.claude/statusline.sh).
#   Needs bash 4.2 or newer and jq; git is optional and only feeds the branch part.
#   Check it: `bash ~/.claude/statusline.sh --selftest`
#
# Where the cost figures come from
#   Every dollar amount is Claude Code's own estimate (`cost.total_cost_usd` in
#   the JSON Claude Code pipes on stdin): token usage x the price list built into
#   Claude Code. This script holds no prices, so new models and price changes
#   arrive with Claude Code updates. Negotiated, Bedrock or Vertex rates are not
#   visible to Claude Code, and on a Pro/Max subscription the figure is what the
#   same usage would cost at API prices. Treat it as an estimate, not an invoice.
#
# Files written (all under $CLAUDE_CONFIG_DIR, default ~/.claude)
#   .cost-ledger           per-day spend and last-seen cost per session
#   .statusline-ctx        recent context sizes per session, for the turns forecast
#   .statusline-unpriced   cached count of this month's sessions with unpriced usage
#
# Performance
#   Claude Code re-runs this script on every update, and process creation is slow
#   on Windows (Git Bash emulates fork), so the script prefers bash builtins
#   (printf -v, integer maths, parameter expansion) over subshells and external
#   tools. Per render it starts jq once and, when the git part shows, git once
#   (twice inside a worktree), and runs stat only when it needs a file's size
#   or age. The unpriced-model scan runs in the background at most once every
#   10 minutes. statusline.conf is read with a builtin loop.
#
# Platform notes
#   * jq.exe and git.exe on Windows may emit CRLF: every line read from them has
#     its trailing \r stripped.
#   * workspace.current_dir arrives as C:\path\to\dir on Windows; backslashes are
#     normalised to / so basename, -d tests and git -C all work.
#   * stat differs between GNU (-c) and BSD/macOS (-f); see file_stat below.

set -uo pipefail

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# bash statusline.sh --selftest  → asserts field order, colour states and the ledger
if [ "${1:-}" = "--selftest" ]; then
  export STATUSLINE_SYNC=1               # run the unpriced scan in the foreground
  unset CLAUDE_CONFIG_DIR                # tests point HOME at throwaway dirs
  fail=0
  # Renders run under "$BASH", the bash running this test, which may not be
  # the first bash on PATH (on macOS that can be Apple's bash 3.2).
  t() { # t <name> <json> <regex-that-must-match>  (ANSI stripped)
    got=$(printf '%s' "$2" | "$BASH" "$0" | sed $'s/\033\\[[0-9;]*m//g')
    if printf '%s' "$got" | grep -qE "$3"; then echo "ok   $1"
    else echo "FAIL $1: got [$got], want /$3/"; fail=1; fi
  }
  traw() { # traw <name> <json> <regex-against-RAW-escapes>
    got=$(printf '%s' "$2" | "$BASH" "$0")
    if printf '%s' "$got" | grep -qE "$3"; then echo "ok   $1"
    else echo "FAIL $1: raw output did not match /$3/"; fail=1; fi
  }
  OPUS1M='{"model":{"id":"claude-opus-5[1m]","display_name":"Opus 5 (1M context)"},"workspace":{"current_dir":"/tmp"},"effort":{"level":"high"},"cost":{"total_cost_usd":1.2345},"context_window":{"context_window_size":1000000,"used_percentage":7,"total_input_tokens":67100}}'
  t "opus 1M high" "$OPUS1M" 'Opus 5 \(1M\)-high \| tmp \| \$1\.23'
  t "no ctx text segment on line 1" "$OPUS1M" '^[^\n]*\$1\.23$'
  traw "1M renders bold" "$OPUS1M" $'\033\\[1;38;5;178m'
  t "effort hidden when absent" \
    '{"model":{"id":"claude-sonnet-5","display_name":"Sonnet 5"},"workspace":{"current_dir":"/tmp"},"cost":{"total_cost_usd":0},"context_window":{"context_window_size":200000,"used_percentage":20,"total_input_tokens":40000}}' \
    'Sonnet 5 \| tmp \| \$0\.00$'
  t "null usage degrades to 0%" \
    '{"model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"/tmp"},"cost":{"total_cost_usd":0},"context_window":{"context_window_size":200000,"used_percentage":null,"current_usage":null}}' \
    '░{10} +0% 0/200\.0k$'
  t "1M at 700k renders 7/10 cells + token counts" \
    '{"model":{"id":"claude-opus-5[1m]","display_name":"Opus 5 (1M context)"},"workspace":{"current_dir":"/tmp"},"effort":{"level":"high"},"cost":{"total_cost_usd":0},"context_window":{"context_window_size":1000000,"used_percentage":70,"total_input_tokens":700000}}' \
    '█{7}░{3} +70% 700\.0k/1\.0M$'
  t "windows backslash cwd shows basename" \
    '{"model":{"id":"claude-sonnet-5","display_name":"S"},"workspace":{"current_dir":"C:\\Users\\nobody\\my-proj"},"cost":{"total_cost_usd":0},"context_window":{"context_window_size":200000,"used_percentage":10,"total_input_tokens":20000}}' \
    'S \| my-proj \| \$0\.00$'
  # per-model heat: each model's thresholds turn the bar amber, orange and red
  # at different percentages
  heat() { # heat <name> <model-id> <window> <pct> <expected-raw-escape>
    traw "$1" \
      "{\"model\":{\"id\":\"$2\"},\"context_window\":{\"context_window_size\":$3,\"used_percentage\":$4,\"total_input_tokens\":$(( $3 * $4 / 100 ))}}" \
      "$5"
  }
  GREYC=$'\033\\[38;5;240m'; AMBER=$'\033\\[38;5;179m'
  ORANGE=$'\033\\[38;5;208m'; RED=$'\033\\[1;38;5;203m'
  heat "haiku at 25% is grey"        claude-haiku-4-5    200000 25 "$GREYC"
  heat "haiku at 50% is amber"       claude-haiku-4-5    200000 50 "$AMBER"
  heat "haiku at 75% is orange"      claude-haiku-4-5    200000 75 "$ORANGE"
  heat "sonnet at 25% is grey"       claude-sonnet-5     200000 25 "$GREYC"
  heat "sonnet at 40% is amber"      claude-sonnet-5     200000 40 "$AMBER"
  heat "opus at 20% is grey"         'claude-opus-5[1m]' 1000000 20 "$GREYC"
  heat "opus at 25% is amber"        'claude-opus-5[1m]' 1000000 25 "$AMBER"
  heat "opus at 50% is orange"       'claude-opus-5[1m]' 1000000 50 "$ORANGE"
  heat "opus at 75% is red"          'claude-opus-5[1m]' 1000000 75 "$RED"
  heat "fable at 20% is amber"       claude-fable-5      200000 20 "$AMBER"
  heat "fable at 40% is orange"      claude-fable-5      200000 40 "$ORANGE"
  heat "fable at 65% is red"         claude-fable-5      200000 65 "$RED"
  heat "unknown model falls back to sonnet thresholds" claude-mystery 200000 40 "$AMBER"
  traw "200k at 160k: 40k left forces orange on haiku (70% alone is amber)" \
    '{"model":{"id":"claude-haiku-4-5"},"context_window":{"context_window_size":200000,"used_percentage":70,"total_input_tokens":160000}}' \
    $'\033\\[38;5;208m'
  traw "200k at 185k: absolute floor forces red even on haiku" \
    '{"model":{"id":"claude-haiku-4-5"},"context_window":{"context_window_size":200000,"used_percentage":92,"total_input_tokens":185000}}' \
    $'\033\\[1;38;5;203m'
  traw "1M at 990k is critical red" \
    '{"model":{"id":"claude-opus-5[1m]"},"context_window":{"context_window_size":1000000,"used_percentage":99,"total_input_tokens":990000}}' \
    $'\033\\[1;38;5;203m'
  t "burn rate divides by API time, not wall clock" \
    '{"model":{"id":"claude-sonnet-5","display_name":"S"},"cost":{"total_cost_usd":2,"total_api_duration_ms":3600000,"total_duration_ms":7200000},"context_window":{"context_window_size":200000,"used_percentage":10,"total_input_tokens":20000}}' \
    '\$2\.00 \(\$2\.00/h\)$'
  t "no rate under a minute of API time" \
    '{"model":{"id":"claude-sonnet-5","display_name":"S"},"cost":{"total_cost_usd":2,"total_api_duration_ms":5000},"context_window":{"context_window_size":200000,"used_percentage":10,"total_input_tokens":20000}}' \
    '\$2\.00$'
  t "wall-clock elapsed is never shown" \
    '{"model":{"id":"claude-sonnet-5","display_name":"S"},"cost":{"total_cost_usd":0,"total_duration_ms":7200000},"context_window":{"context_window_size":200000,"used_percentage":10,"total_input_tokens":20000}}' \
    '\$0\.00$'
  t "churn renders when Claude wrote lines" \
    '{"model":{"id":"claude-sonnet-5"},"cost":{"total_lines_added":142,"total_lines_removed":38},"context_window":{"context_window_size":200000,"used_percentage":10,"total_input_tokens":20000}}' \
    '\+142/-38'
  t "churn absent when nothing was written" \
    '{"model":{"id":"claude-sonnet-5"},"context_window":{"context_window_size":200000,"used_percentage":10,"total_input_tokens":20000}}' \
    '20\.0k/200\.0k$'
  # turns-to-red: drive real samples through a throwaway HOME
  eta_run() { # eta_run <tmpdir> <session> <tokens...>  → stripped output of the last render
    d=$1; sid=$2; shift 2
    mkdir -p "$d/.claude"
    for u in "$@"; do
      printf '{"session_id":"%s","model":{"id":"claude-sonnet-5"},"context_window":{"context_window_size":200000,"used_percentage":10,"total_input_tokens":%d}}' "$sid" "$u" \
        | HOME="$d" "$BASH" "$0" | sed $'s/\033\\[[0-9;]*m//g'
    done | tail -1
  }
  te() { # te <name> <regex> <session> <tokens...>
    name=$1; want=$2; shift 2
    d=$(mktemp -d); got=$(eta_run "$d" "$@"); rm -rf "$d"
    if printf '%s' "$got" | grep -qE "$want"; then echo "ok   $name"
    else echo "FAIL $name: got [$got], want /$want/"; fail=1; fi
  }
  # +10k a turn, target = min(85% of 200k, 200k-20k) = 170k; at 50k that is 12 turns
  te "steady growth predicts turns to red" '~12 turns to red' s1 10000 20000 30000 40000 50000
  te "two samples is not enough evidence" 'k/200\.0k$'  s2 10000 20000
  te "spiky growth refuses to guess"      'k/200\.0k$'  s3 1000 2000 3000 60000
  # plan usage limits: resets an hour and three days out from now
  printf -v tnow '%(%s)T' -1
  # lj <5h pct> <5h reset> [<wk pct> <wk reset>]: the JSON is built by printf
  # from single-quoted formats, because bash 4.2 brace-expands a "{..,..}"
  # literal written inside "$(...)".
  lj() {
    local rl
    if [ "$#" -eq 0 ]; then rl=null
    elif [ "$#" -eq 2 ]; then printf -v rl '{"five_hour":{"used_percentage":%s,"resets_at":%s}}' "$1" "$2"
    else printf -v rl '{"five_hour":{"used_percentage":%s,"resets_at":%s},"seven_day":{"used_percentage":%s,"resets_at":%s}}' "$1" "$2" "$3" "$4"
    fi
    printf '{"model":{"id":"claude-sonnet-5"},"context_window":{"context_window_size":200000,"used_percentage":10,"total_input_tokens":20000},"rate_limits":%s}' "$rl"
  }
  in1h=$(( tnow + 3600 )); in3d=$(( tnow + 259200 )); ago1m=$(( tnow - 60 ))
  t "limits show session and weekly use" "$(lj 42.7 "$in1h" 18 "$in3d")" \
    '\| 5h ███░░ 42% \([0-9]{2}:[0-9]{2}\) · wk █░░░░ 18% \([A-Z][a-z]{2}\)$'
  t "limits absent leave line 2 unchanged" "$(lj)" '20\.0k/200\.0k$'
  t "a window past its reset is hidden" "$(lj 99 "$ago1m" 3 "$in3d")" \
    '200\.0k \| wk █░░░░ 3% '
  traw "limit near the cap turns red" "$(lj 95 "$in1h")" \
    $'5h\033\\[0m \033\\[1;38;5;203m█████ 95%'
  traw "limit under half is grey" "$(lj 20 "$in1h")" \
    $'5h\033\\[0m \033\\[38;5;240m█░░░░ 20%'
  # layout: statusline.conf under a throwaway HOME. Output is ANSI-stripped and
  # ends in "#", so a missing or extra trailing newline is visible to the regex.
  lay() { # lay <name> <conf text, or - for no file> <json> <bash regex>
    local d got
    d=$(mktemp -d); mkdir -p "$d/.claude"
    [ "$2" = - ] || printf '%s' "$2" > "$d/.claude/statusline.conf"
    got=$(printf '%s' "$3" | HOME="$d" "$BASH" "$0" | sed $'s/\033\\[[0-9;]*m//g'; printf '#')
    rm -rf "$d"
    if [[ "$got" =~ $4 ]]; then echo "ok   $1"
    else echo "FAIL $1: got [$got], want /$4/"; fail=1; fi
  }
  NL=$'\n'
  LJ="{\"model\":{\"id\":\"claude-sonnet-5\",\"display_name\":\"S\"},\"workspace\":{\"current_dir\":\"/tmp\"},\"cost\":{\"total_cost_usd\":0,\"total_lines_added\":5,\"total_lines_removed\":2},\"context_window\":{\"context_window_size\":200000,\"used_percentage\":10,\"total_input_tokens\":20000},\"rate_limits\":{\"five_hour\":{\"used_percentage\":8,\"resets_at\":$(( tnow + 3600 ))}}}"
  lay "default layout without a conf file" - "$LJ" \
    "^S [|] tmp [|] [$]0[.]00${NL}█░{9} +10% 20[.]0k/200[.]0k [|] [+]5/-2 [|] 5h █░{4} 8% [(][0-9:]{5}[)]#\$"
  lay "conf order is the render order" $'line1=limits model\nline2=churn context\n' "$LJ" \
    "^5h █░{4} 8% [(][0-9:]{5}[)] [|] S${NL}[+]5/-2 [|] █░{9} +10% 20[.]0k/200[.]0k#\$"
  lay "empty line2 gives a single line" $'line2=\n' "$LJ" \
    "^S [|] tmp [|] [$]0[.]00#\$"
  lay "missing line2 key keeps the default line 2" $'line1=folder\n' "$LJ" \
    "^tmp${NL}█░{9} .* 5h .*#\$"
  lay "empty line1 prints line 2 alone" $'line1=\nline2=context\n' "$LJ" \
    "^█░{9} +10% 20[.]0k/200[.]0k#\$"
  lay "unknown names, comments and CRLF are tolerated" \
    $'# my layout\r\nline1 = model bogus folder  # trailing note\r\nline2=nope context\r\n' "$LJ" \
    "^S [|] tmp${NL}█░{9} +10% 20[.]0k/200[.]0k#\$"
  # hidden parts skip their work: no ledger or samples file is written
  d=$(mktemp -d); mkdir -p "$d/.claude"; printf 'line1=model\nline2=context\n' > "$d/.claude/statusline.conf"
  for u in 10000 20000; do
    printf '{"session_id":"h1","model":{"id":"claude-sonnet-5","display_name":"S"},"cost":{"total_cost_usd":%s},"context_window":{"context_window_size":200000,"used_percentage":10,"total_input_tokens":%d}}' "0.$u" "$u" \
      | HOME="$d" "$BASH" "$0" >/dev/null
  done
  if [ ! -e "$d/.claude/.cost-ledger" ] && [ ! -e "$d/.claude/.statusline-ctx" ]; then
    echo "ok   hidden spend and forecast write no files"
  else echo "FAIL hidden spend/forecast still wrote: $(ls -A "$d/.claude" | tr '\n' ' ')"; fail=1; fi
  rm -rf "$d"
  # git segment against a real repo: the porcelain=v2 parse is the only
  # non-trivial string work here, so it is tested end to end. Without git these
  # checks are skipped: the status line then just leaves the branch part out.
  gjson() { printf '{"model":{"id":"claude-sonnet-5","display_name":"S"},"workspace":{"current_dir":"%s"},"cost":{"total_cost_usd":0},"context_window":{"context_window_size":200000,"used_percentage":10,"total_input_tokens":20000}}' "$1"; }
  if command -v git >/dev/null 2>&1; then
    g=$(mktemp -d)
    ( cd "$g" && git init -q . && git config user.email t@t && git config user.name t &&
      git config core.autocrlf false &&
      printf 'a\n' > a.txt && printf 'b\n' > b.txt && git add . && git commit -qm init &&
      printf 'x\n' >> a.txt && printf 'y\n' >> b.txt ) >/dev/null 2>&1
    t "git renders branch + dirty count" "$(gjson "$g")" '(main|master) ±2 \|'
    gwin=$(cygpath -w "$g" 2>/dev/null || printf '%s' "$g"); gwin=${gwin//\\/\\\\}
    t "git works with a Windows-style cwd" "$(gjson "$gwin")" '(main|master) ±2 \|'
    ( cd "$g" && git add -A && git commit -qm clean ) >/dev/null 2>&1
    t "clean tree shows no ± marker" "$(gjson "$g")" '(main|master) \|'
    lay "hidden git part does not appear" $'line1=model folder cost\nline2=\n' "$(gjson "$g")" \
      "^S [|] [^|]+ [|] [$]0[.]00#\$"
    rm -rf "$g"
  else
    for n in "git renders branch + dirty count" "git works with a Windows-style cwd" \
             "clean tree shows no ± marker" "hidden git part does not appear"; do
      echo "skip $n (git not installed)"
    done
  fi
  t "non-repo cwd emits no git segment" "$(gjson /tmp)" 'S \| tmp \| \$0\.00$'
  t "garbage stdin degrades, never errors" 'not json' '.*'
  # The path is set outside "$(...)": inside it, bash 4.2 joins "-$$" and the
  # next word, so the render command never runs.
  nohome=/nonexistent-$$
  err=$(printf '{"session_id":"e1","model":{"id":"claude-sonnet-5"},"context_window":{"context_window_size":200000,"used_percentage":10,"total_input_tokens":20000}}' \
    | HOME="$nohome" "$BASH" "$0" 2>&1 >/dev/null)
  if [ -z "$err" ]; then echo "ok   nothing on stderr when the config dir is missing"
  else echo "FAIL stderr not empty: [$err]"; fail=1; fi
  # cost ledger: deltas per session, summed across sessions, no double counting
  d=$(mktemp -d); mkdir -p "$d/.claude"
  cj() { printf '{"session_id":"%s","model":{"id":"claude-sonnet-5","display_name":"S"},"cost":{"total_cost_usd":%s},"context_window":{"context_window_size":200000,"used_percentage":10,"total_input_tokens":20000}}' "$1" "$2"; }
  l1() { cj "$@" | HOME="$d" "$BASH" "$0" | head -1 | sed $'s/\033\\[[0-9;]*m//g'; }
  for args in "a 1.0" "a 1.5" "a 1.5" "b 0.25"; do got=$(l1 $args); done
  if printf '%s' "$got" | grep -qE 'today \$1\.75 · [A-Za-z]+ \$1\.75$'; then echo "ok   ledger sums session deltas"
  else echo "FAIL ledger: got [$got]"; fail=1; fi
  printf -v td '%(%Y-%m)T' -1
  printf 'D %s-00 2000000\nD 1999-01-01 9000000\n' "$td" >> "$d/.claude/.cost-ledger"
  got=$(l1 b 0.5)
  if printf '%s' "$got" | grep -qE 'today \$2\.00 · [A-Za-z]+ \$4\.00$'; then echo "ok   month adds earlier days, ignores other months"
  else echo "FAIL ledger month: got [$got]"; fail=1; fi
  # unpriced warning: a finished session this month whose log carries the flag
  mkdir -p "$d/.claude/projects/p"
  printf '{"type":"cost-state","hasUnknownModelCost":true}\n' > "$d/.claude/projects/p/s.jsonl"
  printf '{"type":"cost-state","hasUnknownModelCost":false}\n' > "$d/.claude/projects/p/t.jsonl"
  rm -f "$d/.claude/.statusline-unpriced"
  got=$(l1 b 0.5)
  if printf '%s' "$got" | grep -qE '\$4\.00 ⚠ 1 unpriced$'; then echo "ok   unpriced sessions are flagged"
  else echo "FAIL unpriced: got [$got]"; fail=1; fi
  rm -rf "$d"
  exit $fail
fi

# builtin read instead of $(cat): one fewer process
IFS= read -r -d '' INPUT || true

DIM=$'\033[2m'; RESET=$'\033[0m'
GREY=$'\033[38;5;245m'
# set variable $1 to a colour escape with printf -v, so no subshell fork
c256()  { printf -v "$1" '\033[38;5;%sm' "$2"; }      # foreground
c256b() { printf -v "$1" '\033[1;38;5;%sm' "$2"; }    # bold foreground

# file_stat <var> <size|mtime> <path>: GNU stat first, BSD/macOS stat if that fails.
# The order matters: on GNU, `stat -f` means "filesystem status" and prints junk.
file_stat() {
  local gnu=%s bsd=%z out
  [ "$2" = mtime ] && gnu=%Y bsd=%m
  out=$(stat -c "$gnu" "$3" 2>/dev/null || stat -f "$bsd" "$3" 2>/dev/null)
  out=${out%$'\r'}
  [[ "$out" =~ ^[0-9]+$ ]] || out=0
  printf -v "$1" '%s' "$out"
}

# Layout: $CFG/statusline.conf picks the parts and their order (see "Layout"
# in the header). Read with a builtin loop, so it costs no extra process.
L1="model folder git cost spend"; L2="context churn forecast limits"
if [ -f "$CFG/statusline.conf" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}; line=${line%%#*}
    case "$line" in *=*) ;; *) continue ;; esac
    key=${line%%=*}; key=${key//[[:space:]]/}
    case "$key" in
      line1) L1=${line#*=} ;;
      line2) L2=${line#*=} ;;
    esac
  done < "$CFG/statusline.conf"
fi
show_model=""; show_folder=""; show_git=""; show_cost=""; show_spend=""
show_context=""; show_churn=""; show_forecast=""; show_limits=""
lay1=(); lay2=()
# keep known names only, each once; a part listed on both lines stays on the first
for n in $L1; do
  case "$n" in model|folder|git|cost|spend|context|churn|forecast|limits) ;; *) continue ;; esac
  v=show_$n; [ -n "${!v}" ] && continue
  printf -v "$v" 1; lay1+=("$n")
done
for n in $L2; do
  case "$n" in model|folder|git|cost|spend|context|churn|forecast|limits) ;; *) continue ;; esac
  v=show_$n; [ -n "${!v}" ] && continue
  printf -v "$v" 1; lay2+=("$n")
done
p_model=""; p_folder=""; p_git=""; p_cost=""; p_spend=""
p_context=""; p_churn=""; p_forecast=""; p_limits=""

# 1. one jq pass, one field per line. Never tab-split: bash collapses runs of
#    tabs (tab is IFS whitespace), so an empty field would shift every later one.
#    `// 0` also absorbs an explicit null. The burn rate and micro-dollar cost
#    are computed here so bash never needs float maths.
fields=()
# ($'\r' is not expanded inside double quotes, so strip in a bare assignment.)
while IFS= read -r line; do line=${line%$'\r'}; fields+=("$line"); done < <(
  printf '%s' "$INPUT" | jq -r '
    (.model.id // ""),
    (.model.display_name // ""),
    (.workspace.current_dir // .cwd // ""),
    (.cost.total_cost_usd // 0),
    (.effort.level // ""),
    ((.context_window.context_window_size // 0) | floor),
    ((.context_window.used_percentage // 0) | floor),
    ((.context_window.total_input_tokens // 0) | floor),
    (.session_id // ""),
    ((.cost.total_api_duration_ms // 0) | floor),
    ((.cost.total_lines_added // 0) | floor),
    ((.cost.total_lines_removed // 0) | floor),
    ((.cost.total_cost_usd // 0) as $c | (.cost.total_api_duration_ms // 0) as $a
      | if ($a >= 60000) and ($c | type == "number") then $c * 3600000 / $a else "" end),
    ((.cost.total_cost_usd // 0) | if type == "number" then (. * 1000000 | floor) else 0 end),
    (.rate_limits.five_hour.used_percentage | if type == "number" then floor else "" end),
    (.rate_limits.five_hour.resets_at | if type == "number" then floor else "" end),
    (.rate_limits.seven_day.used_percentage | if type == "number" then floor else "" end),
    (.rate_limits.seven_day.resets_at | if type == "number" then floor else "" end)' 2>/dev/null
)
model_id=${fields[0]:-}
model=${fields[1]:-}
cwd=${fields[2]:-}
cost=${fields[3]:-}
effort=${fields[4]:-}
ctx_size=${fields[5]:-0}
ctx_pct=${fields[6]:-0}
ctx_used=${fields[7]:-0}
session_id=${fields[8]:-}
added=${fields[10]:-0}
removed=${fields[11]:-0}
rate=${fields[12]:-}
cost_u=${fields[13]:-0}                  # session cost in micro-dollars
lim5_pct=${fields[14]:-}                 # plan limits: empty when not on Pro/Max
lim5_at=${fields[15]:-}                  #   or before the session's first reply
lim7_pct=${fields[16]:-}
lim7_at=${fields[17]:-}

for v in ctx_size ctx_pct ctx_used added removed cost_u; do
  eval "[[ \"\${$v}\" =~ ^[0-9]+$ ]] || $v=0"
done

cwd=${cwd//\\//}                         # C:\Users\me\proj → C:/Users/me/proj
cwd_base=${cwd%/}; cwd_base=${cwd_base##*/}

# 2. model tier hue (matched on the id, not the display name), its five effort
#    shades, and the context-heat percentages "notice warn critical" for that
#    tier. Tiers that use up plan limits faster get stricter thresholds, so a
#    colour means roughly the same spend whichever model is running.
case "$model_id" in
  *haiku*)  tier=244; shades="238 241 244 248 252"; thr="50 75 90" ;;
  *sonnet*) tier=73;  shades="66 72 73 80 87";      thr="40 65 85" ;;
  *opus*)   tier=178; shades="94 136 178 220 227";  thr="25 50 75" ;;
  *fable*)  tier=167; shades="95 131 167 203 210";  thr="20 40 65" ;;
  *)        tier=244; shades="238 241 244 248 252"; thr="40 65 85" ;;
esac
case "$effort" in
  low)    idx=1 ;;
  medium) idx=2 ;;
  high)   idx=3 ;;
  xhigh)  idx=4 ;;
  max)    idx=5 ;;
  *)      idx=0 ;;   # absent / unsupported → no suffix at all
esac

if [ -n "$show_model" ] && [ -n "$model" ]; then
  label=$model
  if [ "$ctx_size" -eq 1000000 ]; then
    label="${label/ (1M context)/}"      # shortened to a bold " (1M)" marker
    c256b col "$tier"; label="${col}${label} (1M)${RESET}"
  else
    c256 col "$tier"; label="${col}${label}${RESET}"
  fi
  if [ "$idx" -gt 0 ]; then
    read -r -a shade_arr <<<"$shades"
    shade=${shade_arr[idx-1]}
    if [ "$effort" = max ]; then c256b col "$shade"; else c256 col "$shade"; fi
    label="${label}${DIM}-${RESET}${col}${effort}${RESET}"
  fi
  p_model=$label
fi

[ -n "$show_folder" ] && [ -n "${cwd_base:-}" ] && p_folder="${GREY}${cwd_base}${RESET}"

# 3. git: branch ±dirty ↑ahead ↓behind from ONE `git status --porcelain=v2
#    --branch` call, which carries the branch name, the ahead/behind pair and the
#    dirty list. Never touches the network, so ↓behind is exact only against the
#    last fetch: it renders dim once FETCH_HEAD is over 30 minutes old.
if [ -n "$show_git" ] && [ -n "${cwd:-}" ] && [ -d "$cwd" ]; then
  branch=""; dirty=0; ahead=0; behind=0
  # Each .git/index entry is 62 bytes plus the file's path, so 12MB is roughly
  # 100k tracked files. Past that, `git status` is too slow for a status line and
  # only the branch is shown. Checked only when the working folder is the repo root.
  idx_bytes=0
  [ -f "$cwd/.git/index" ] && file_stat idx_bytes size "$cwd/.git/index"
  if [ "$idx_bytes" -gt 12000000 ]; then
    branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
    branch=${branch%$'\r'}
  else
    gs=$(git --no-optional-locks -C "$cwd" status --porcelain=v2 --branch -uno 2>/dev/null)
    while IFS= read -r line; do
      line=${line%$'\r'}
      case "$line" in
        '# branch.head '*) branch=${line#\# branch.head } ;;
        '# branch.ab '*)   ab=${line#\# branch.ab }
                           ahead=${ab%% *}; ahead=${ahead#+}
                           behind=${ab##* }; behind=${behind#-} ;;
        '# '*) ;;
        ?*)    dirty=$(( dirty + 1 )) ;;
      esac
    done <<< "$gs"
  fi
  [[ "$ahead"  =~ ^[0-9]+$ ]] || ahead=0
  [[ "$behind" =~ ^[0-9]+$ ]] || behind=0

  if [ -n "$branch" ] && [ "$branch" != HEAD ] && [ "$branch" != "(detached)" ]; then
    seg="${DIM}${branch}${RESET}"
    if [ "$dirty" -gt 0 ]; then c256 col 179; seg="${seg} ${col}±${dirty}${RESET}"; fi
    if [ "$ahead" -gt 0 ]; then c256 col 72;  seg="${seg} ${col}↑${ahead}${RESET}"; fi
    if [ "$behind" -gt 0 ]; then
      gitdir="$cwd/.git"                 # worktrees keep the real git dir elsewhere
      if [ ! -d "$gitdir" ]; then
        gitdir=$(git -C "$cwd" rev-parse --absolute-git-dir 2>/dev/null)
        gitdir=${gitdir%$'\r'}
      fi
      file_stat fetched mtime "$gitdir/FETCH_HEAD"
      printf -v now '%(%s)T' -1
      if [ $(( now - fetched )) -gt 1800 ]; then
        seg="${seg} ${DIM}↓${behind}${RESET}"
      else
        c256 col 179; seg="${seg} ${col}↓${behind}${RESET}"
      fi
    fi
    p_git=$seg
  fi
fi

# 4. session cost + burn rate. The rate divides by API time, not wall clock, so
#    walking away from the keyboard does not make the session look cheap.
if [ -n "$show_cost" ] && [[ "${cost:-}" =~ ^[0-9.]+([eE][-+]?[0-9]+)?$ ]]; then
  printf -v money0 '%.2f' "$cost" 2>/dev/null || money0=$cost
  cseg="${DIM}\$${money0}${RESET}"
  if [[ "$rate" =~ ^[0-9.]+([eE][-+]?[0-9]+)?$ ]]; then
    printf -v money1 '%.2f' "$rate" 2>/dev/null && cseg="${cseg} ${DIM}(\$${money1}/h)${RESET}"
  fi
  p_cost=$cseg
fi

# 5. today / this month, from a ledger of the same per-session estimate.
#    $CFG/.cost-ledger holds two kinds of line:
#      S <session_id> <micro$>   last cost seen for that session (newest 200 kept)
#      D <YYYY-MM-DD> <micro$>   spend attributed to that day (kept forever)
#    Each render adds (session cost now - last seen) to today, so a session that
#    runs past midnight splits correctly. A cost that went DOWN means a fresh
#    counter, and the whole value counts. Only sessions that render a status line
#    are counted: headless `claude -p` runs never reach this script.
#    A mkdir lock serialises concurrent sessions; a render that loses the race
#    skips the write, and its delta lands on the next render instead.
LEDGER="$CFG/.cost-ledger"
printf -v today '%(%Y-%m-%d)T' -1
printf -v mon_name '%(%b)T' -1
printf -v now '%(%s)T' -1
month=${today%-*}
if [ -n "$show_spend" ] && [ -n "${session_id:-}" ] && [ -d "$CFG" ]; then
  lock="$LEDGER.lock"
  if [ -d "$lock" ]; then                # a killed render leaves its lock behind
    file_stat lt mtime "$lock"
    [ $(( now - lt )) -gt 10 ] && rmdir "$lock" 2>/dev/null
  fi
  locked=0; mkdir "$lock" 2>/dev/null && locked=1

  last=-1; day_u=0; mon_u=0; s_lines=(); d_lines=""
  if [ -f "$LEDGER" ]; then
    while read -r kind key val; do
      val=${val%$'\r'}
      [[ "$val" =~ ^[0-9]+$ ]] || continue
      case "$kind" in
        S) if [ "$key" = "$session_id" ]; then last=$val; else s_lines+=("S $key $val"); fi ;;
        D) if [ "$key" = "$today" ]; then day_u=$val; else
             d_lines="${d_lines}D $key $val"$'\n'
             [ "${key%-*}" = "$month" ] && mon_u=$(( mon_u + val ))
           fi ;;
      esac
    done < "$LEDGER"
  fi

  if [ "$last" -lt 0 ] || [ "$cost_u" -lt "$last" ]; then delta=$cost_u
  else delta=$(( cost_u - last )); fi
  if [ "$locked" -eq 1 ] && [ "$delta" -gt 0 ]; then
    day_u=$(( day_u + delta ))
    [ "${#s_lines[@]}" -gt 199 ] && s_lines=("${s_lines[@]:$(( ${#s_lines[@]} - 199 ))}")
    { [ "${#s_lines[@]}" -gt 0 ] && printf '%s\n' "${s_lines[@]}"
      printf 'S %s %s\n%sD %s %s\n' "$session_id" "$cost_u" "$d_lines" "$today" "$day_u"
    } > "$LEDGER.$$" 2>/dev/null && mv -f "$LEDGER.$$" "$LEDGER" 2>/dev/null || rm -f "$LEDGER.$$" 2>/dev/null
  fi
  [ "$locked" -eq 1 ] && rmdir "$lock" 2>/dev/null
  mon_u=$(( mon_u + day_u ))

  printf -v d_txt '%d.%02d' $(( day_u / 1000000 )) $(( (day_u % 1000000) / 10000 ))
  printf -v m_txt '%d.%02d' $(( mon_u / 1000000 )) $(( (mon_u % 1000000) / 10000 ))
  lseg="${DIM}today \$${d_txt} · ${mon_name} \$${m_txt}${RESET}"

  # Unpriced usage: when Claude Code meets a model missing from its price list,
  # it sets "hasUnknownModelCost": true in the session log's cost record. That
  # record is written when a session ends and is not in the status line JSON,
  # so this counts FINISHED sessions this month (by log mtime); a running
  # session shows up after it ends. The scan runs in the background at most
  # every 10 minutes and caches "<YYYY-MM> <epoch> <count>".
  UNPRICED="$CFG/.statusline-unpriced"
  u_mon=""; u_at=0; u_n=0
  [ -f "$UNPRICED" ] && read -r u_mon u_at u_n < "$UNPRICED"
  u_n=${u_n%$'\r'}
  [[ "$u_at" =~ ^[0-9]+$ ]] || u_at=0
  [[ "$u_n" =~ ^[0-9]+$ ]] || u_n=0
  [ "$u_mon" = "$month" ] || u_n=0
  if [ "$u_mon" != "$month" ] || [ $(( now - u_at )) -gt 600 ]; then
    printf '%s %s %s\n' "$month" "$now" "$u_n" > "$UNPRICED" 2>/dev/null   # claim this refresh
    scan_unpriced() {
      local n
      n=$(find "$CFG/projects" -name '*.jsonl' -newermt "$month-01" \
            -exec grep -lE '"hasUnknownModelCost": *true' {} + 2>/dev/null | wc -l)
      n=${n//[!0-9]/}
      printf '%s %s %s\n' "$month" "$now" "${n:-0}" > "$UNPRICED.$$" 2>/dev/null &&
        mv -f "$UNPRICED.$$" "$UNPRICED" 2>/dev/null
      u_n=${n:-0}
    }
    if [ -n "${STATUSLINE_SYNC:-}" ]; then scan_unpriced
    else ( scan_unpriced ) >/dev/null 2>&1 </dev/null & fi
  fi
  if [ "$u_n" -gt 0 ]; then c256 col 179; lseg="${lseg} ${col}⚠ ${u_n} unpriced${RESET}"; fi
  p_spend=$lseg
fi

# ── context bar, percentage, tokens used / window size ──────────────────────
# human <var> <n> → 1.2k / 67.1k / 1.0M: one decimal place keeps the figure short.
# Pure bash: printf parses "67100e-3" as a float.
human() {
  local n=$2
  if   [ "$n" -ge 1000000 ]; then printf -v "$1" '%.1fM' "${n}e-6"
  elif [ "$n" -ge 1000 ];    then printf -v "$1" '%.1fk' "${n}e-3"
  else                            printf -v "$1" '%d' "$n"
  fi
}

# Bar colour is the WORSE of two tests. The per-model percentage says "you are
# spending"; the absolute tokens-remaining floor (50k / 20k) says "you are about
# to compact". Together, red never arrives late on a 1M window and never early
# on a cheap model.
# The forecast reuses this state and colour, so it is computed for either part.
state=0                                  # 0 ok, 1 notice, 2 warn, 3 critical
read -r t_notice t_warn t_crit <<<"${thr:-40 65 85}"
bar_c=""
if [ -n "$show_context" ] || [ -n "$show_forecast" ]; then
if   [ "$ctx_pct" -ge "$t_crit" ];   then state=3
elif [ "$ctx_pct" -ge "$t_warn" ];   then state=2
elif [ "$ctx_pct" -ge "$t_notice" ]; then state=1
fi
if [ "$ctx_size" -gt 0 ]; then
  remaining=$(( ctx_size - ctx_used ))
  [ "$remaining" -lt 0 ] && remaining=0
  if   [ "$remaining" -lt 20000 ]; then abs=3
  elif [ "$remaining" -lt 50000 ]; then abs=2
  else                                  abs=0
  fi
  [ "$abs" -gt "$state" ] && state=$abs
fi
case "$state" in
  3) c256b bar_c 203 ;;
  2) c256  bar_c 208 ;;
  1) c256  bar_c 179 ;;
  *) c256  bar_c 240 ;;
esac
fi

if [ -n "$show_context" ]; then
  width=10
  pct_clamped=$ctx_pct
  [ "$pct_clamped" -gt 100 ] && pct_clamped=100
  filled=$(( pct_clamped * width / 100 ))
  bar=""
  for ((i = 0; i < width; i++)); do
    if [ "$i" -lt "$filled" ]; then bar="${bar}█"; else bar="${bar}░"; fi
  done
  printf -v p_context '%s%s %3d%%%s' "$bar_c" "$bar" "$ctx_pct" "$RESET"
  if [ "$ctx_size" -gt 0 ]; then
    human hu "$ctx_used"; human hs "$ctx_size"
    p_context="${p_context} ${DIM}${hu}/${hs}${RESET}"
  fi
fi

# churn: lines CLAUDE wrote via Edit/Write this session. Not `git diff`: your own
# edits are absent and a line written then reverted still counts.
if [ -n "$show_churn" ] && { [ "$added" -gt 0 ] || [ "$removed" -gt 0 ]; }; then
  c256 cg 71; c256 cr 167
  p_churn="${cg}+${added}${RESET}${DIM}/${RESET}${cr}-${removed}${RESET}"
fi

# ── turns until the bar goes red ─────────────────────────────────────────────
# Extrapolates the median per-turn context growth from this session's last few
# samples. Counted in turns, not minutes, because idle time would wreck a clock
# estimate. It predicts THIS script's red threshold, not Claude Code's
# auto-compact trigger (which is not exposed). Silent until there are >= 3
# growth steps, and when growth is spiky: one big file read can add 50k at once.
# Concurrent sessions writing at the same instant are last-write-wins; the
# loser re-samples on its next render.
SAMPLES="$CFG/.statusline-ctx"
if [ -n "$show_forecast" ] && [ -n "${session_id:-}" ] && [ "$ctx_size" -gt 0 ] && [ "$ctx_used" -gt 0 ] && [ "$state" -lt 3 ]; then
  t_pct=$(( ctx_size * t_crit / 100 ))
  t_abs=$(( ctx_size - 20000 ))
  target=$t_pct; [ "$t_abs" -lt "$target" ] && target=$t_abs

  prev=""; rest=""; n=0
  if [ -f "$SAMPLES" ]; then
    while IFS= read -r line; do
      line=${line%$'\r'}
      case "$line" in
        "$session_id "*) prev=${line#* } ;;
        ?*) n=$((n+1)); [ "$n" -le 19 ] && rest="${rest}${line}"$'\n' ;;
      esac
    done < "$SAMPLES"
  fi
  # a re-render without a new turn is not a sample: record only when the number moved
  if [ "${prev##* }" != "$ctx_used" ] && [ -d "$CFG" ]; then
    prev="${prev:+$prev }$ctx_used"
    read -r -a samples <<<"$prev"
    [ "${#samples[@]}" -gt 6 ] && samples=("${samples[@]:$(( ${#samples[@]} - 6 ))}")
    prev="${samples[*]}"
    { printf '%s%s %s\n' "$rest" "$session_id" "$prev" > "$SAMPLES.$$" &&
      mv -f "$SAMPLES.$$" "$SAMPLES" || rm -f "$SAMPLES.$$"; } 2>/dev/null
  fi

  eta=""
  read -r -a a <<<"$prev"
  dd=()
  for ((i = 1; i < ${#a[@]}; i++)); do
    [[ "${a[i]}" =~ ^[0-9]+$ && "${a[i-1]}" =~ ^[0-9]+$ ]] || continue
    d=$(( a[i] - a[i-1] )); [ "$d" -gt 0 ] && dd+=("$d")
  done
  m=${#dd[@]}
  if [ "$m" -ge 3 ]; then
    for ((i = 0; i < m; i++)); do for ((j = i + 1; j < m; j++)); do
      if [ "${dd[j]}" -lt "${dd[i]}" ]; then tmp=${dd[i]}; dd[i]=${dd[j]}; dd[j]=$tmp; fi
    done; done
    med=${dd[(m + 1) / 2 - 1]}
    left=$(( target - ctx_used ))
    # refuse when the largest step is over 4x the median (spiky growth)
    if [ "$med" -gt 0 ] && [ "${dd[m-1]}" -le $(( 4 * med )) ] && [ "$left" -gt 0 ]; then
      tt=$(( (2 * left + med) / (2 * med) ))          # round(left / med)
      [ "$tt" -lt 1 ] && tt=1
      [ "$tt" -le 99 ] && eta=$tt                      # beyond 99 is not news
    fi
  fi
  [ -n "$eta" ] && p_forecast="${DIM}~${eta} turns to${RESET} ${bar_c}red${RESET}"
fi

# ── plan usage limits (Pro/Max): the same bars as /usage and the desktop app ─
# limit_seg <label> <pct> <resets_at epoch> → appends "5h ███░░ 42% (19:40)" to $lim.
# Heat colours: grey under 50% (the context bar's "ok" grey), yellow from 50,
# orange from 75, bold red from 90.
# The 5-cell bar rounds up, so any use at all shows one cell (as the app does).
# The reset shows as a clock time when it is under a day away, else a weekday.
# A window whose reset has already passed is stale until the next reply: hidden.
lim=""
limit_seg() {
  local p=$2 at=$3 when col bar="" i fill
  [[ "$p" =~ ^[0-9]+$ ]] || return
  [[ "$at" =~ ^[0-9]+$ ]] && [ "$at" -le "$now" ] && return
  if   [ "$p" -ge 90 ]; then c256b col 203
  elif [ "$p" -ge 75 ]; then c256  col 208
  elif [ "$p" -ge 50 ]; then c256  col 179
  else                       c256  col 240
  fi
  fill=$(( (p * 5 + 99) / 100 )); [ "$fill" -gt 5 ] && fill=5
  for ((i = 0; i < 5; i++)); do
    if [ "$i" -lt "$fill" ]; then bar="${bar}█"; else bar="${bar}░"; fi
  done
  when=""
  if [[ "$at" =~ ^[0-9]+$ ]]; then
    if [ $(( at - now )) -lt 86400 ]; then printf -v when ' (%(%H:%M)T)' "$at"
    else printf -v when ' (%(%a)T)' "$at"; fi
  fi
  lim="${lim:+$lim${DIM} · ${RESET}}${DIM}$1${RESET} ${col}${bar} $p%${RESET}${DIM}${when}${RESET}"
}
if [ -n "$show_limits" ]; then
  limit_seg 5h "$lim5_pct" "$lim5_at"
  limit_seg wk "$lim7_pct" "$lim7_at"
  p_limits=$lim
fi

# ── output: each line joins its non-empty parts with a dim " | " ───────────
# join_parts <var> <part names...>
join_parts() {
  local _dst=$1 _out="" n v
  shift
  for n in "$@"; do
    v=p_$n; [ -n "${!v}" ] || continue
    _out="${_out:+$_out${DIM} | ${RESET}}${!v}"
  done
  printf -v "$_dst" '%s' "$_out"
}
join_parts out1 ${lay1[@]+"${lay1[@]}"}
join_parts out2 ${lay2[@]+"${lay2[@]}"}
# Every printed line but the last ends in "\n"; an empty line is not printed.
if [ -n "$out1" ] && [ -n "$out2" ]; then printf '%s\n%s' "$out1" "$out2"
else printf '%s' "$out1$out2"; fi
