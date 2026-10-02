# Contributing

Bug reports, fixes and small features are welcome.

## Before you start

For anything larger than a small fix, open an issue first so we can agree on the approach.

## Making a change

1. Fork the repo and create a branch from `main`.
2. Make your change in `statusline.sh` or `install.sh`.
3. Add a check to the self-test block at the top of `statusline.sh` for any new behaviour.
4. Run the tests:
   ```bash
   bash statusline.sh --selftest
   ```
   The checks match the bar's block characters, so the terminal must use UTF-8. If two checks fail on the bar, run `export LC_ALL=C.UTF-8` (macOS: `en_US.UTF-8`) first.

   To try the installer without touching your real Claude Code settings, point it at a scratch folder with `CLAUDE_CONFIG_DIR`. Both commands then work only inside that folder:
   ```bash
   CLAUDE_CONFIG_DIR=/tmp/cc-test bash install.sh
   CLAUDE_CONFIG_DIR=/tmp/cc-test bash install.sh --uninstall
   ```
5. Open a pull request. CI runs the self-test on macOS, Linux and Windows, plus ShellCheck.

`main` is protected: every change lands through a pull request with passing CI, and is squash-merged.

## Style

- **Speed matters.** Claude Code re-runs the script on every update, and starting a process is slow on Windows. Prefer bash builtins (`printf -v`, `[[ ]]`, parameter expansion) over `$(...)`, `sed`, `awk` or extra `jq` calls.
- **Portable.** It must run on bash 4.2+ on macOS (BSD tools), Linux (GNU tools) and Git Bash on Windows. Strip a trailing `\r` from anything read from `jq` or `git`.
- **No network calls and no hard-coded prices.** Cost figures come only from Claude Code's `cost.total_cost_usd`.

## Code of conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md).
