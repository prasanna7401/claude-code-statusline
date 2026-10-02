# Changelog

All notable changes are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-10-02

### Added

- `limits` part: plan usage in the 5-hour and weekly windows (Pro/Max), with small bars coloured by use and the reset time.
- `statusline.conf` layout file: `line1=` and `line2=` choose which parts show, on which line, in what order; an empty `line2=` gives one line.
- `install.sh` layout menu (in a terminal), `--defaults` to skip it, and a preview render at the end.
- Self-test grows to 53 checks.

### Changed

- Line 2 parts are separated by ` | `, like line 1.
- Hidden parts skip their work: no git call, ledger or forecast file for a part that is not shown.
- `install.sh --uninstall` also removes `statusline.conf`.
- README shortened.

## [1.0.0] - 2026-10-02

### Added

- Two-line status line: model and effort, folder, git branch status, session cost and burn rate, spend today and this month, unpriced-model warning, context-window bar, lines changed, turns-left forecast.
- `--selftest` with 40 checks.
- `install.sh` with `--uninstall`.

[1.1.0]: https://github.com/prasanna7401/claude-code-statusline/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/prasanna7401/claude-code-statusline/releases/tag/v1.0.0
