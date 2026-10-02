# claude-code-statusline

[![CI](https://github.com/prasanna7401/claude-code-statusline/actions/workflows/ci.yml/badge.svg)](https://github.com/prasanna7401/claude-code-statusline/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A two-line status bar for [Claude Code](https://claude.com/claude-code) that shows what you are spending and how full Claude's memory is, at a glance.

![Three examples of the status line in a dark terminal. Top: Sonnet with a grey bar at 18%. Middle: Opus with an amber bar at 34%. Bottom: Sonnet with a red bar at 91%.](docs/statusline.svg)

The picture is real output from the script at three moments: early in a session, halfway, and nearly full. As plain text, one status line looks like this:

```
Opus 5.5 (1M)-high | my-project | main ±4 ↑1 | $0.52 ($9.87/h) | today $3.10 · Oct $41.20
░░░░░░░░░░   7% 67.1k/1.0M  +142/-38  ~12 turns to red
```

It sits at the bottom of the Claude Code window and updates as you work. It makes no network calls and sends nothing anywhere.

## Contents

- [📊 What it shows](#-what-it-shows)
- [✅ Requirements](#-requirements)
- [📦 Install](#-install)
- [🔄 Updating](#-updating)
- [🧪 Check it works](#-check-it-works)
- [🛠️ Troubleshooting](#️-troubleshooting)
- [❓ FAQ](#-faq)
- [🗑️ Uninstall](#️-uninstall)
- [📁 Files it writes](#-files-it-writes)
- [💰 How accurate are the costs?](#-how-accurate-are-the-costs)
- [🤝 Contributing](#-contributing)
- [📄 Licence](#-licence)

## 📊 What it shows

**Line 1**

| Example | What it means |
|---|---|
| `Opus 5.5 (1M)-high` | The model you are using. `(1M)` appears when the model has the large one-million-token memory. The last word is the effort level you picked in Claude Code: how hard the model thinks before answering (`low`, `medium`, `high`, `xhigh` or `max`). The effort part is hidden when the model has none. |
| `my-project` | The folder Claude Code is working in. |
| `main ±4 ↑1` | The git branch: the line of work you are on, if this folder is a git project. `±4` means 4 files have changes not yet committed (saved into git's history). Brand-new files that git does not track yet are not counted. `↑1` means 1 commit not yet pushed (sent to the shared copy, such as GitHub). `↓2` means 2 commits are waiting to be pulled (brought down from the shared copy), as of your last `git fetch`, because the script never goes online. `↓` turns dim when that fetch is over 30 minutes old, as a hint that the number may be out of date. |
| `$0.52 ($9.87/h)` | Estimated cost of this session so far. The figure in brackets is the cost per hour of Claude actively working, not per hour on the clock, so idle time does not lower it. |
| `today $3.10 · Oct $41.20` | Estimated spend today and this month, across all your sessions. |
| `⚠ 2 unpriced` | Appears when, this month, Claude Code met a model it has no price for. The number counts this month's Claude Code session log files that carry that flag. Usage in those sessions is missing from the totals, so the totals read low. |

**Line 2**

| Example | What it means |
|---|---|
| `░░░░░░░░░░   7%` | How full the context window is. The context window is Claude's working memory for this conversation. When it fills up, Claude Code summarises older detail to make room. Each of the 10 cells stands for 10%, so at 7% no cell is filled yet. The bar changes colour as it fills (see below). |
| `67.1k/1.0M` | Tokens used out of the total available. A token is roughly three-quarters of a word. |
| `+142/-38` | Lines of code Claude has added and removed in this session. Your own edits are not counted. |
| `~12 turns to red` | A rough forecast of how many more back-and-forth turns fit before the bar turns red, based on how fast the bar has been filling. |

### Bar colours

Grey means plenty of room. Amber means worth noticing, orange means getting full, and red means close to the limit. Models that cost more switch colour sooner, so a colour means roughly the same spend whatever model you use.

| Model | Amber from | Orange from | Red from |
|---|---|---|---|
| Haiku | 50% | 75% | 90% |
| Sonnet (and any model not listed) | 40% | 65% | 85% |
| Opus | 25% | 50% | 75% |
| Fable | 20% | 40% | 65% |

Whatever the model, the bar is at least orange when fewer than 50k tokens are left, and red when fewer than 20k are left.

Other colours:

- The model name is coloured by model family. The effort word gets brighter from `low` to `max`, and `max` is bold.
- In the git part, `±` and an up-to-date `↓` are amber, and `↑` is green.
- `⚠ N unpriced` is amber.

### When parts are hidden

- **Branch.** Hidden outside a git project, when git is not installed, and when no branch is checked out. In very large git projects (roughly 100,000 files or more) only the branch name is shown, without `±`, `↑` or `↓`, to keep the status line fast. That size check only happens when Claude Code is working in the project's top folder.
- **Cost per hour.** Hidden until Claude has worked for a minute.
- **Lines changed.** Hidden until Claude has added or removed a line.
- **Turns to red.** Hidden for the first few turns of a session, when growth is too uneven to predict (one large file read can add 50k tokens at once), when more than 99 turns remain, and once the bar is already red. It predicts this status line's red, not the moment Claude Code starts summarising.

## ✅ Requirements

- **bash 4.2 or newer.** bash is the program that runs the script. Linux and Git Bash on Windows already have a new enough one. macOS ships an older bash (3.2), so you install a newer one (steps below).
- **jq**, a small tool for reading JSON (the data format Claude Code sends to the status line).
- **git**, used to download this project and to show the branch. git is optional for the status line itself: without it, the branch part is left out and everything else works. Without git, you can download the project as a ZIP file instead (see below).

## 📦 Install

The installer does three things:

1. It copies the script into your Claude Code settings folder.
2. It adds the `statusLine` entry to `settings.json`, keeping a backup of the old file at `settings.json.bak`. If you already had a `statusLine` entry, it shows it and replaces it.
3. It runs the built-in self-test, a set of 40 quick checks that confirm the script works on your computer.

Pick your system:

<details>
<summary><b>🍎 macOS</b></summary>

Open Terminal and paste:

```bash
brew install bash jq git
git clone https://github.com/prasanna7401/claude-code-statusline.git
cd claude-code-statusline
bash install.sh
```

No Homebrew? Get it from [brew.sh](https://brew.sh) first.

If the installer says your bash is too old, Terminal is still finding Apple's older bash before the new one. Run the installer with the new bash by its full path:

```bash
/opt/homebrew/bin/bash install.sh
```

On Intel Macs, use `/usr/local/bin/bash install.sh`. The installer handles the rest: it writes that full path into `settings.json`, so Claude Code also uses the new bash.

</details>

<details>
<summary><b>🐧 Linux</b></summary>

Open a terminal and paste (Debian or Ubuntu; on Fedora use `sudo dnf install jq git`):

```bash
sudo apt install jq git
git clone https://github.com/prasanna7401/claude-code-statusline.git
cd claude-code-statusline
bash install.sh
```

</details>

<details>
<summary><b>🪟 Windows (Git Bash)</b></summary>

Claude Code on Windows uses Git Bash, which comes with [Git for Windows](https://git-scm.com/download/win). Installing Git for Windows also gives you git.

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

If Git Bash says `jq is not installed`, close every Git Bash window and open a new one, so it picks up the newly installed program. If it still fails, restart Windows. Restart Claude Code too, so it can find jq.

</details>

### Without git: download the ZIP

The `git clone` step above needs git. Without it, open the project's GitHub page, click the green **Code** button, then **Download ZIP**. Unzip it, open a terminal in the unzipped folder (`claude-code-statusline-main`), and run `bash install.sh`. You still need bash and jq as described above.

### After installing

Restart Claude Code. The two lines appear at the bottom of the window.

### Installing by hand

If you prefer not to run the installer:

1. Copy the file `statusline.sh` from this project into your Claude Code settings folder, so it sits at `~/.claude/statusline.sh`. (`~` means your home folder: `/Users/<you>` on macOS, `/home/<you>` on Linux, `C:\Users\<you>` on Windows. Folders starting with a dot are hidden by default. On macOS, press Cmd+Shift+. in Finder to show them.)
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

   **On macOS**, if `bash --version` in Terminal shows version 3.2, use the new bash's full path instead of `bash`, for example:
   `"command": "/opt/homebrew/bin/bash ~/.claude/statusline.sh"`

3. Restart Claude Code.

If you keep Claude Code's settings somewhere other than `~/.claude` (by setting the `CLAUDE_CONFIG_DIR` environment variable), use that folder instead. The installer and the script both follow it.

## 🔄 Updating

From the folder you cloned, run:

```bash
git pull
bash install.sh
```

If you downloaded the ZIP, download it again and run `bash install.sh` from the new folder. On macOS, if you installed with `/opt/homebrew/bin/bash install.sh`, update with that same command.

Your cost history is kept: the installer only replaces the script and the `statusLine` setting. Keep the project folder, because updating and the uninstall command both run from it.

Updating copies the project's script over the installed one, so changes you made to `~/.claude/statusline.sh` itself are lost. Make your changes in the project folder's copy instead.

## 🧪 Check it works

Run the built-in self-test:

```bash
bash ~/.claude/statusline.sh --selftest
```

It runs 40 checks in throwaway folders and prints `ok` for each. Any line starting with `FAIL` describes what went wrong. Without git, the 3 git checks print `skip` instead, and the rest still run. The test never touches your real cost history.

## 🛠️ Troubleshooting

**Nothing appears at the bottom of Claude Code.** Restart Claude Code. Then check that `~/.claude/settings.json` has the `statusLine` entry, and run `bash ~/.claude/statusline.sh --selftest`.

**Line 1 is empty and the bar always shows 0%.** Claude Code cannot find jq. Install it (see Install) and restart Claude Code. On Windows, restart Windows if a new Git Bash window still cannot find it.

**The status line shows strange errors or nothing at all on macOS.** Claude Code is starting Apple's old bash 3.2. Run the installer again with `/opt/homebrew/bin/bash install.sh` (Intel Macs: `/usr/local/bin/bash install.sh`). If you installed by hand, put the new bash's full path at the start of the `command` value in `settings.json`, for example `"/opt/homebrew/bin/bash ~/.claude/statusline.sh"`.

**The bar shows boxes or question marks.** Your terminal font or language setting does not support the block characters. Use a UTF-8 terminal (the default on macOS, most Linux systems and Git Bash).

**The self-test fails "renders 7/10 cells" or "degrades to 0%".** Your terminal is not using UTF-8, the text encoding that covers the bar's block characters. Run `export LC_ALL=C.UTF-8` (macOS: `export LC_ALL=en_US.UTF-8`) and try again.

**The self-test prints 3 `skip` lines for git.** git is not installed. The status line still works, without the branch part.

**The daily total looks low.** Totals only count sessions since you installed the status line. See [How accurate are the costs?](#-how-accurate-are-the-costs) below.

**`↓` shows a number that seems out of date.** The script never goes online, so `↓` only knows what your last `git fetch` (or `git pull`) brought in. Run `git fetch` to refresh it.

## ❓ FAQ

**Does it slow Claude Code down?** Not noticeably. Each update starts only a few small programs (jq, git and sometimes stat) and makes no network calls. On Windows, where starting programs is slowest, one update takes around a fifth of a second. The search for unpriced sessions runs in the background, at most once every 10 minutes.

**Does it cost anything or use my tokens?** No. It only reads numbers Claude Code already has.

**Does it send my data anywhere?** No. It makes no network calls. It reads what Claude Code passes to it, your git project and Claude Code's own session logs, and writes three small files in your settings folder.

**Does it work with a Pro or Max subscription?** Yes. The dollar figures then show what the same usage would cost at Anthropic's pay-as-you-go prices, not what you are charged. See [How accurate are the costs?](#-how-accurate-are-the-costs).

**Can I run several Claude Code sessions at once?** Yes. The daily and monthly totals add up all of them, and each session keeps its own turns-to-red forecast.

**Can I change the colours or thresholds?** Yes. Edit the table in section 2 of `statusline.sh` (the `case "$model_id"` lines). Make the change in the project folder's copy and run `bash install.sh` again, because updating replaces the installed copy.

## 🗑️ Uninstall

From the project folder:

```bash
bash install.sh --uninstall
```

This removes the `statusLine` entry from `settings.json` (keeping a backup at `settings.json.bak`), deletes the script and deletes the files it wrote. Restart Claude Code afterwards.

To uninstall by hand, delete the `"statusLine"` entry from `~/.claude/settings.json`, then delete `~/.claude/statusline.sh` and the three files listed below.

## 📁 Files it writes

All three live in your Claude Code settings folder (`~/.claude`, or `$CLAUDE_CONFIG_DIR` if set). They are small text files and safe to delete. Deleting `.cost-ledger` resets your daily and monthly totals.

| File | What it holds |
|---|---|
| `.cost-ledger` | Spend per day, and the last cost seen for each session, so totals are not double-counted. |
| `.statusline-ctx` | Recent context sizes per session, used for the turns-to-red forecast. |
| `.statusline-unpriced` | A cached count of this month's sessions with unpriced usage, refreshed at most every 10 minutes. |

The script also reads Claude Code's own session logs in the `projects` folder inside the same settings folder, to find unpriced sessions. It never changes them.

## 💰 How accurate are the costs?

Treat every dollar figure as an **estimate, not an invoice**.

- **Where the numbers come from.** Claude Code calculates a running cost for each session from the tokens used and its built-in price list. This script only displays and adds up that figure. It holds no prices of its own, so new models and price changes arrive when you update Claude Code.
- **List prices only.** Discounts, negotiated company rates, and prices you pay when using Claude through Amazon Bedrock or Google Vertex (cloud providers that resell Claude) are not visible to Claude Code, so the figure uses Anthropic's standard pay-as-you-go prices.
- **Subscriptions.** On a Pro or Max plan you do not pay per token. The figure shows what the same usage would have cost at pay-as-you-go prices, which is useful for comparison but is not money you were charged.
- **Scripted runs are not counted.** The status line only runs when you are chatting with Claude Code in its window. Runs started from a script or command, such as `claude -p "..."`, never show it, so their cost never reaches the daily or monthly totals.
- **The unpriced warning is late.** Claude Code records the "no price for this model" flag when a session ends, so `⚠ N unpriced` only counts finished sessions. A session that is still running shows up after it ends.
- **Totals start from install day.** The daily and monthly figures only include sessions seen since you installed the status line. Earlier spending is not back-filled, so your first month will read low.
- **Each settings folder keeps its own totals.** If you use more than one `CLAUDE_CONFIG_DIR`, each has a separate ledger.

## 🤝 Contributing

Bug reports, fixes and small features are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for how to make and test a change, and [SECURITY.md](SECURITY.md) for reporting a security problem privately.

## 📄 Licence

MIT. See [LICENSE](LICENSE).
