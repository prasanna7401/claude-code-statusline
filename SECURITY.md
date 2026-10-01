# Security policy

## Reporting a problem

Please report security issues privately through
[GitHub's private vulnerability reporting](https://github.com/prasanna7401/claude-code-statusline/security/advisories/new),
not as a public issue. You should get a reply within a week.

## What is in scope

The status line runs on every Claude Code update with your user's permissions. Relevant problems include:

- input from Claude Code (model names, folder paths, branch names) being executed as a command;
- the installer damaging or leaking the contents of `settings.json`;
- the script reading or writing files outside the Claude Code config folder, other than the git repo it reports on.

The script makes no network calls and holds no credentials.

## Supported versions

Only the latest release receives fixes.
