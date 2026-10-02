#!/usr/bin/env bash
# install.sh: installs or removes claude-code-statusline.
#
#   bash install.sh              copy statusline.sh into the Claude config dir,
#                                point settings.json at it, ask which parts to
#                                show and where (only when run in a terminal),
#                                run the self-test and show a preview
#   bash install.sh --defaults   the same, with no questions: every part, in
#                                the default layout
#   bash install.sh --uninstall  remove the statusLine setting, the script,
#                                statusline.conf and the files the script writes
#
# The config dir is $CLAUDE_CONFIG_DIR, or ~/.claude when that is unset.
# settings.json is backed up to settings.json.bak before every change.
# The layout menu runs only when stdin is a terminal; INSTALL_FORCE_MENU=1 runs
# it with piped input, so tests can feed it answers.

set -euo pipefail

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CFG/settings.json"
TARGET="$CFG/statusline.sh"
CONF="$CFG/statusline.conf"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "error: $*" >&2; exit 1; }

mode=install; defaults=0
for arg in "$@"; do
  case "$arg" in
    --uninstall) mode=uninstall ;;
    --defaults)  defaults=1 ;;
    -h|--help)   sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option: $arg (use --defaults, --uninstall or --help)" ;;
  esac
done

command -v jq >/dev/null 2>&1 || die "jq is not installed. See the README for how to install it."

# Writes settings.json through jq, keeping a backup of the previous version.
edit_settings() { # edit_settings <jq-filter> [jq args...]
  local filter=$1; shift
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
  jq -e . "$SETTINGS" >/dev/null 2>&1 || die "$SETTINGS is not valid JSON; fix it by hand first."
  cp "$SETTINGS" "$SETTINGS.bak"
  jq "$@" "$filter" "$SETTINGS.bak" > "$SETTINGS.tmp"
  mv -f "$SETTINGS.tmp" "$SETTINGS"
}

if [ "$mode" = uninstall ]; then
  if [ -f "$SETTINGS" ]; then
    edit_settings 'del(.statusLine)'
    echo "Removed statusLine from $SETTINGS (backup: settings.json.bak)"
  fi
  rm -f "$TARGET" "$CONF" "$CFG/.cost-ledger" "$CFG/.statusline-ctx" "$CFG/.statusline-unpriced"
  echo "Removed statusline.sh, statusline.conf and the status line's data files from $CFG"
  echo "Restart Claude Code to finish."
  exit 0
fi

# The status line needs bash 4.2+. The bash running this installer is the one
# that gets checked, runs the self-test and goes into settings.json, so on macOS
# `/opt/homebrew/bin/bash install.sh` works even when Apple's bash 3.2 is first
# on PATH.
if [ "${BASH_VERSINFO[0]}" -lt 4 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 2 ]; }; then
  die "bash $BASH_VERSION is too old; 4.2 or newer is needed. On macOS: brew install bash, then run /opt/homebrew/bin/bash install.sh (Intel Macs: /usr/local/bin/bash install.sh)"
fi

# settings.json says plain "bash" when that finds this same bash, and this
# bash's full path when the first bash on PATH is a different one.
runner=bash
path_bash=$(command -v bash 2>/dev/null || true)
if [ -z "$path_bash" ] || ! [ "$BASH" -ef "$path_bash" ]; then
  runner="\"$BASH\""
fi

mkdir -p "$CFG"
cp "$HERE/statusline.sh" "$TARGET"

# Git Bash on Windows: Claude Code needs a C:/... path, not /c/...
path="$TARGET"
command -v cygpath >/dev/null 2>&1 && path="$(cygpath -m "$TARGET")"

if [ -f "$SETTINGS" ] && old=$(jq -c '.statusLine // empty' "$SETTINGS" 2>/dev/null) && [ -n "$old" ]; then
  echo "Replacing your existing statusLine setting: $old"
fi
edit_settings '.statusLine = {type: "command", command: ($b + " \"" + $p + "\"")}' --arg b "$runner" --arg p "$path"
echo "Installed $TARGET"
echo "Set statusLine in $SETTINGS (backup: settings.json.bak)"
echo

# ── layout: which parts show, on which line, in what order ──────────────────
# The menu's result is two space-separated lists, L1 and L2. statusline.conf is
# written only when they differ from the script's built-in default.
PARTS=(model folder git cost spend context churn forecast limits)
EXAMPLES=(
  "Opus 5.5 (1M)-high"
  "my-project"
  "main ±4 ↑1"
  "\$0.52 (\$9.87/h)"
  "today \$3.10 · Oct \$41.20"
  "░░░░░░░░░░   7% 67.1k/1.0M"
  "+142/-38"
  "~12 turns to red"
  "5h █░░░░ 8% · wk █░░░░ 2%"
)
DEF1="model folder git cost spend"
DEF2="context churn forecast limits"
ticked=(1 1 1 1 1 1 1 1 1)

# ask <prompt>: prints the prompt and reads one line into $answer, without the
# trailing \r a Windows terminal can add. Input that ends early is an error, so
# a re-ask loop never spins forever.
ask() {
  printf '%s' "$1"
  if ! IFS= read -r answer; then echo; die "input ended before the layout was chosen; no layout file was written."; fi
  answer=${answer%$'\r'}
}

is_ticked() { # is_ticked <part name>
  local i
  for i in "${!PARTS[@]}"; do
    [ "${PARTS[i]}" = "$1" ] && [ "${ticked[i]}" = 1 ] && return 0
  done
  return 1
}

keep_ticked() { # keep_ticked <list>: prints the list without unticked parts
  local n out=""
  for n in $1; do is_ticked "$n" && out="${out:+$out }$n"; done
  printf '%s' "$out"
}

pick_parts() {
  local i n bad any
  while :; do
    echo "Parts of the status line ([x] = shown):"
    for i in "${!PARTS[@]}"; do
      if [ "${ticked[i]}" = 1 ]; then n=x; else n=" "; fi
      printf '  [%s] %d %-9s %s\n' "$n" $(( i + 1 )) "${PARTS[i]}" "${EXAMPLES[i]}"
    done
    ask "Type numbers to untick or tick (for example: 3 5), or press Enter to accept: "
    if [ -z "${answer//[[:space:]]/}" ]; then
      any=0; for i in "${ticked[@]}"; do [ "$i" = 1 ] && any=1; done
      [ "$any" = 1 ] && break
      echo "Tick at least one part."; continue
    fi
    bad=""
    for n in $answer; do [[ "$n" =~ ^[1-9]$ ]] || bad="${bad:+$bad }$n"; done
    if [ -n "$bad" ]; then echo "Not a part number (1-9): $bad"; continue; fi
    for n in $answer; do i=$(( n - 1 )); ticked[i]=$(( 1 - ticked[i] )); done
  done
}

# ask_line <prompt> <blank allowed: 0|1> <names already placed>: re-asks until
# every name is a ticked part named once, then sets $answer to the clean list.
ask_line() {
  local n bad seen words
  while :; do
    ask "$1"
    bad=""; seen=" $3 "
    read -r -a words <<<"$answer" || true
    for n in ${words[@]+"${words[@]}"}; do
      if ! is_ticked "$n"; then bad="\"$n\" is not a ticked part"; break; fi
      case "$seen" in *" $n "*) bad="\"$n\" is named twice"; break ;; esac
      seen="$seen$n "
    done
    if [ -n "$bad" ]; then echo "  $bad. Ticked parts: $(keep_ticked "${PARTS[*]}")"; continue; fi
    if [ "$2" = 0 ] && [ "${#words[@]}" -eq 0 ]; then echo "  Line 1 needs at least one part."; continue; fi
    answer="${words[*]-}"
    return
  done
}

choose_layout() {
  local n placed
  pick_parts
  echo
  echo "Default layout:  line 1: $(keep_ticked "$DEF1")"
  echo "                 line 2: $(keep_ticked "$DEF2")"
  ask "Keep the default layout? [Y/n] "
  case "$answer" in
    n|N|no|No|NO)
      echo "Type part names separated by spaces. Any ticked part you do not place is added to the end of the last line."
      ask_line "Line 1 order: " 0 ""; L1=$answer
      ask_line "Line 2 order (blank for one line): " 1 "$L1"; L2=$answer
      placed=" $L1 $L2 "
      for n in $(keep_ticked "${PARTS[*]}"); do
        case "$placed" in *" $n "*) continue ;; esac
        if [ -n "$L2" ]; then L2="$L2 $n"; else L1="$L1 $n"; fi
      done ;;
    *)
      L1=$(keep_ticked "$DEF1"); L2=$(keep_ticked "$DEF2") ;;
  esac
}

menu=0
if [ "$defaults" = 0 ] && { [ -t 0 ] || [ -n "${INSTALL_FORCE_MENU:-}" ]; }; then menu=1; fi

if [ "$menu" = 0 ]; then
  if [ -f "$CONF" ]; then echo "Keeping your layout file, $CONF"
  else echo "Layout: the default, every part shown. Run bash install.sh in a terminal to choose."; fi
else
  keep=0
  if [ -f "$CONF" ]; then
    echo "You already have a layout file, $CONF:"
    grep -E '^[[:space:]]*line[12][[:space:]]*=' "$CONF" | sed 's/^/  /' || true
    ask "Keep it? [Y/n] "
    case "$answer" in n|N|no|No|NO) ;; *) keep=1 ;; esac
  fi
  if [ "$keep" = 1 ]; then
    echo "Keeping $CONF"
  else
    choose_layout
    if [ "$L1" = "$DEF1" ] && [ "$L2" = "$DEF2" ]; then
      if [ -f "$CONF" ]; then rm -f "$CONF"; echo "Removed $CONF: the default layout needs no file."; fi
      echo "Layout: the default."
    else
      printf '# Status line layout, written by install.sh. Parts:\n# model folder git cost spend context churn forecast limits\nline1=%s\nline2=%s\n' \
        "$L1" "$L2" > "$CONF"
      echo "Wrote $CONF"
    fi
  fi
fi
echo

echo "Running the self-test..."
if report=$("$BASH" "$TARGET" --selftest); then
  grep '^skip' <<<"$report" || true
  echo "All $(grep -c '^ok' <<<"$report") checks passed."
else
  grep -v '^ok' <<<"$report" || true
  die "some checks failed (listed above)."
fi
echo

# ── preview: sample data rendered with the chosen layout ────────────────────
# Runs against a throwaway config dir seeded with a spend ledger and context
# samples, so every part has something to show and real files stay untouched.
pv=$(mktemp -d)
[ -f "$CONF" ] && cp "$CONF" "$pv/statusline.conf"
printf -v now '%(%s)T' -1
printf -v today '%(%Y-%m-%d)T' -1
printf 'S preview 520000\nD %s 3100000\n' "$today" > "$pv/.cost-ledger"
printf 'preview 20000 30000 40000 50000\n' > "$pv/.statusline-ctx"
sample=$(jq -cn --arg cwd "$HERE" --argjson r5 $(( now + 7200 )) --argjson r7 $(( now + 259200 )) '{
  session_id: "preview",
  model: {id: "claude-sonnet-5", display_name: "Sonnet 5"},
  effort: {level: "high"},
  workspace: {current_dir: $cwd},
  cost: {total_cost_usd: 0.52, total_api_duration_ms: 190000,
         total_lines_added: 142, total_lines_removed: 38},
  context_window: {context_window_size: 200000, used_percentage: 30, total_input_tokens: 60000},
  rate_limits: {five_hour: {used_percentage: 8, resets_at: $r5},
                seven_day: {used_percentage: 2, resets_at: $r7}}}')
echo "Preview with sample data:"
echo
printf '%s' "$sample" | CLAUDE_CONFIG_DIR="$pv" STATUSLINE_SYNC=1 "$BASH" "$TARGET" || true
echo
echo
rm -rf "$pv"
echo "Restart Claude Code to see the status line."
echo "To change the layout later, run bash install.sh again or edit $CONF"
