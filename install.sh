#!/usr/bin/env bash
# install.sh: installs or removes claude-code-statusline.
#
#   bash install.sh              copy statusline.sh into the Claude config dir,
#                                point settings.json at it, run the self-test
#   bash install.sh --uninstall  remove the statusLine setting, the script and
#                                the files it writes
#
# The config dir is $CLAUDE_CONFIG_DIR, or ~/.claude when that is unset.
# settings.json is backed up to settings.json.bak before every change.

set -euo pipefail

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CFG/settings.json"
TARGET="$CFG/statusline.sh"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "error: $*" >&2; exit 1; }

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

if [ "${1:-}" = "--uninstall" ]; then
  if [ -f "$SETTINGS" ]; then
    edit_settings 'del(.statusLine)'
    echo "Removed statusLine from $SETTINGS (backup: settings.json.bak)"
  fi
  rm -f "$TARGET" "$CFG/.cost-ledger" "$CFG/.statusline-ctx" "$CFG/.statusline-unpriced"
  echo "Removed statusline.sh and its data files from $CFG"
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

echo "Running the self-test..."
if report=$("$BASH" "$TARGET" --selftest); then
  grep '^skip' <<<"$report" || true
  echo "All $(grep -c '^ok' <<<"$report") checks passed."
else
  grep -v '^ok' <<<"$report" || true
  die "some checks failed (listed above)."
fi
echo "Restart Claude Code to see the status line."
