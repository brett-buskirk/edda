# Changelog

All notable changes to edda are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.1] — 2026-07-18

### Fixed
- `read` now renders **straight to the terminal**, so `glow`/`bat` detect the TTY and colorize. It
  had been capturing the renderer's output first (to measure length for paging), which makes `glow`
  fall back to plain text — so `edda read <note>` looked like `cat`, while `edda read <note> | glow`
  worked. Paging is now delegated to each renderer (`glow -p`, `bat --paging`) so the color survives
  it, and note length is judged from the raw body. Covered by a regression test.

## [0.4.0] — 2026-07-18

### Added
- **`mv` / `rename`** — rename a note: the new name becomes both the filename slug and the
  frontmatter `title:`, kept in sync (`created` and the body untouched). A new name that slugs to the
  same filename is a title-only change in place. Never overwrites a different existing note (refuses
  on collision), and refuses a missing source or an unsluggable new name. Ships with harness tests:
  rename + title sync + created/body preserved, same-slug retitle, collision, and the error paths.

## [0.3.0] — 2026-07-18

### Added
- **`labels`** — with no note, list every label in use across the vault, by descending count. Given a
  `<note>`, show its labels, or edit them with `-a/--add` and `-r/--remove` (both repeatable), which
  rewrite the closed `labels:` field in place (slugified; a duplicate add or absent remove is a
  no-op, and an edit bumps `updated:`). Ships with harness tests: overview counts, show, add/remove,
  and the no-op cases.

### Changed
- `new` drops an unsluggable `-l` label value instead of writing a stray empty entry into `labels:`
  — `new` and `labels` now share one `fmt_labels` writer for the closed `labels:` form.

## [0.2.0] — 2026-07-18

### Added
- **`rm`** — soft-delete a note to `$EDDA_VAULT/.trash/`, **never a hard delete**. Confirms once via
  vegtam's `/dev/tty` `confirm()` gate (so a piped stdin can't auto-confirm) or `--force` to skip. A
  second delete of the same name is timestamp-suffixed rather than clobbered; restore by moving the
  file back out of `.trash/`. Ships with harness tests: lands-in-`.trash`, the `/dev/tty` safety
  gate, missing-note, and no-clobber.

## [0.1.1] — 2026-07-18

### Changed
- `search`'s `grep -r` fallback (used when `rg` isn't installed) is now case-insensitive and uses
  extended regex (`-iE`), matching `rg`'s default behavior — so a search finds the same notes whether
  or not `rg` is present, and `|` alternation works either way. (`rg` keeps its smart-case default.)

## [0.1.0] — 2026-07-18

### Added
- The `edda` script — one self-contained Bash file (`set -uo pipefail`) implementing the v1 verb
  surface behind the locked design decisions:
  - **`init`** — scaffold the vault (+ `.trash/`) and a starter config.
  - **`new`** — create a note with the closed frontmatter schema (`title` / `created` / `updated` /
    `labels`); `-l/--label` to seed labels, `-e/--edit` to open it afterwards. Refuses to clobber.
  - **`edit`** — open a note in `$VISUAL` → `$EDITOR` → `nano` → `vi`, bumping `updated:` only when
    the file actually changed.
  - **`add`** — append a line: plain by default (blank-line-separated), `-t/--timestamp` for a
    journal bullet that stacks contiguously, and a lone `-` to read from stdin (guarded against
    hanging on a tty).
  - **`read`** — render through `glow` → `bat` → a minimal built-in render → `cat`, paging long
    notes through `$PAGER`; `--raw` dumps source, `--no-pager` skips paging. Pipe-safe: plain
    markdown with zero escapes when piped or under `NO_COLOR`.
  - **`list`/`ls`** — notes newest-`updated` first, with `-l/--label` (or positional) filtering.
  - **`search`/`grep`** — search the vault with `rg` when present, else `grep -r`; skips `.trash/`.
  - **`path`** — print a note's file path (plain, for scripting).
  - Verb-first grammar with the **bareword fast-path** (`edda <note>` reads an existing note),
    two-level help, and a `NO_COLOR`/non-TTY-aware palette.
  - Vault + config resolution on the `env > config file > default` ladder.
- `.github/workflows/shellcheck.yml` — the `bash -n` + `shellcheck` CI gate the pack runs.
- `.github/workflows/test.yml` and `test/run.sh` — a throwaway-vault test harness (63 assertions)
  covering creation + frontmatter, label filtering, `add`/`-t`/stdin, slug edge cases, `edit`'s
  `updated`-bump + multi-word `$EDITOR`, frontmatter-vs-horizontal-rule, pipe-safety (zero escapes),
  the render and `grep` fallbacks, and the vault resolution ladder.
- README rewritten for adoption; ROADMAP populated with the shipped milestone and what's next.

### Notes
- `rm` is intentionally **not** in v1 — it ships in a later milestone, and only with the
  `.trash/` soft-delete contract (never a hard delete). See [ROADMAP.md](ROADMAP.md).
