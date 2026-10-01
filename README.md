# claude-code-statusline

A two-line status bar for [Claude Code](https://claude.com/claude-code) that shows what you are spending and how full Claude's memory is, at a glance.

```
Opus 5.5 (1M)-high | my-project | main ±4 ↑1 | $0.52 ($9.87/h) | today $3.10 · Oct $41.20
█░░░░░░░░░   7% 67.1k/1.0M  +142/-38  ~12 turns to red
```

It sits at the bottom of the Claude Code window and updates as you work. It makes no network calls and sends nothing anywhere.

## What it shows

**Line 1**

| Example | What it means |
|---|---|
| `Opus 5.5 (1M)-high` | The model you are using, its context size if larger than usual, and the effort level. |
| `my-project` | The folder Claude Code is working in. |
| `main ±4 ↑1` | The git branch. `±4` means 4 files have changes not yet committed (brand-new files git does not track yet are not counted). `↑1` means 1 commit not yet pushed. `↓` means commits waiting to be pulled, as of your last `git fetch`, since the script never goes online. Hidden outside a git repo. |
| `$0.52 ($9.87/h)` | Estimated cost of this session so far, and how fast it is growing per hour. |
| `today $3.10 · Oct $41.20` | Estimated spend today and this month, across all your sessions. |
| `⚠ 2 unpriced` | Appears only when Claude Code could not price a model in some sessions this month, so the totals are too low. |

**Line 2**

| Example | What it means |
|---|---|
| `█░░░░░░░░░   7%` | How full the context window is. The context window is Claude's working memory for this conversation; when it fills up, older detail gets summarised. The bar changes colour as it fills. |
| `67.1k/1.0M` | Tokens used out of the total available. A token is roughly three-quarters of a word. |
| `+142/-38` | Lines of code Claude has added and removed in this session. |
| `~12 turns to red` | A rough forecast of how many more back-and-forth turns fit before the bar turns red, based on how fast it has been filling. |

## Requirements

- **bash 4.2 or newer.** Linux and Git Bash on Windows already have it. macOS ships an older bash (3.2), so install a newer one (below).
- **jq**, a small tool for reading JSON data.
- **git** (optional). Without it the branch segment is simply hidden.

## Install

The installer copies the script into your Claude Code settings folder, adds the `statusLine` entry to `settings.json` (keeping a backup at `settings.json.bak`), and runs the self-test.

### macOS

Open Terminal and paste:

```bash
brew install bash jq git
git clone https://github.com/prasanna7401/claude-code-statusline.git
cd claude-code-statusline
bash install.sh
```

No Homebrew? Get it from [brew.sh](https://brew.sh) first.

If the installer says your bash is too old, your Terminal is still finding Apple's bash first. Run it with the new one instead: `/opt/homebrew/bin/bash install.sh` (on Intel Macs, `/usr/local/bin/bash install.sh`). Then change `"bash ` at the start of the `command` value in `~/.claude/settings.json` to that same full path.

### Linux

Open a terminal and paste (Debian or Ubuntu; on Fedora use `sudo dnf install jq git`):

```bash
sudo apt install jq git
git clone https://github.com/prasanna7401/claude-code-statusline.git
cd claude-code-statusline
bash install.sh
```

### Windows (Git Bash)

Claude Code on Windows uses Git Bash, which comes with [Git for Windows](https://git-scm.com/download/win).

1. Install jq. Open PowerShell and run:
   ```powershell
   winget install jqlang.jq
   ```
2. Close PowerShell. Open **Git Bash** (from the Start menu) and paste:
   ```bash
   git clone https://github.com/prasanna7401/claude-code-statusline.git
   cd claude-code-statusline
   bash install.sh
   ```

If Git Bash says `jq is not installed`, close and reopen Git Bash so it picks up the new program.

### After installing

Restart Claude Code. The two lines appear at the bottom of the window.

### Installing by hand

If you prefer not to run the installer:

1. Save `statusline.sh` as `~/.claude/statusline.sh`.
2. Open `~/.claude/settings.json` (create it if missing) and add the `statusLine` entry:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash ~/.claude/statusline.sh"
     }
   }
   ```

   If the file already has other settings, add only the `"statusLine": { ... }` part inside the existing outer braces, with a comma after the entry before it.

   **On Windows**, use the full path with forward slashes, for example:
   `"command": "bash C:/Users/yourname/.claude/statusline.sh"`

3. Restart Claude Code.

If you keep Claude Code's settings somewhere other than `~/.claude` (by setting the `CLAUDE_CONFIG_DIR` environment variable), use that folder instead. The installer and the script both follow it.

## Check it works

Run the built-in self-test:

```bash
bash ~/.claude/statusline.sh --selftest
```

It runs 40 checks in throwaway folders and prints `ok` for each. Any line starting with `FAIL` describes what went wrong. The test never touches your real cost history.

## Uninstall

From the folder you cloned:

```bash
bash install.sh --uninstall
```

This removes the `statusLine` entry from `settings.json` (keeping a backup at `settings.json.bak`), deletes the script and deletes the files it wrote. Restart Claude Code afterwards.

To uninstall by hand, delete the `"statusLine"` entry from `~/.claude/settings.json`, then delete `~/.claude/statusline.sh` and the three files listed below.

## Files it writes

All three live in your Claude Code settings folder (`~/.claude`, or `$CLAUDE_CONFIG_DIR` if set). They are small text files and safe to delete; deleting `.cost-ledger` resets your daily and monthly totals.

| File | What it holds |
|---|---|
| `.cost-ledger` | Spend per day, and the last cost seen for each session, so totals are not double-counted. |
| `.statusline-ctx` | Recent context sizes per session, used for the turns-left forecast. |
| `.statusline-unpriced` | A cached count of this month's sessions with unpriced usage, refreshed at most every 10 minutes. |

The script also reads Claude Code's own session logs in `~/.claude/projects` to find unpriced sessions. It never changes them.

## How accurate are the costs?

Treat every dollar figure as an **estimate, not an invoice**.

- **Where the numbers come from.** Claude Code calculates a running cost for each session from the tokens used and its built-in API price list. This script only displays and adds up that figure. It holds no prices of its own, so new models and price changes arrive when you update Claude Code.
- **List prices only.** Discounts, negotiated rates, and pricing through Amazon Bedrock or Google Vertex are not visible to Claude Code, so the figure uses standard API prices.
- **Subscriptions.** On a Pro or Max plan you do not pay per token. The figure shows what the same usage would have cost at API prices, which is useful for comparison but is not money you were charged.
- **Headless runs are not counted.** The status line only runs in interactive Claude Code sessions. Scripted runs such as `claude -p "..."` never show it, so their cost never reaches the daily or monthly totals.
- **The unpriced warning is late.** `⚠ N unpriced` only counts sessions that have finished. A session that is still running shows up after it ends.
- **Totals start from install day.** The daily and monthly figures only include sessions seen since you installed the status line. Earlier spending is not back-filled, so your first month will read low.
- **Each settings folder keeps its own totals.** If you use more than one `CLAUDE_CONFIG_DIR`, each has a separate ledger.

## Licence

MIT. See [LICENSE](LICENSE).
