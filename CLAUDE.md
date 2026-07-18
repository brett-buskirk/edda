# CLAUDE.md — Edda

Working manual for a Claude Code agent editing **this** repo. Two parent files auto-load above it via
the directory walk and own the universal rules — this file does **not** restate them:

- **`/etc/claude-code/CLAUDE.md`** (machine policy) — the chain of command (branch → PR → **Brett
  merges**; never self-merge, never commit to `main`), signed commits, the safety floors, brand
  positioning, NIST AI RMF.
- **`~/github-repos/CLAUDE.md`** (estate manual) — issue/PR wiring (assignee `brett-buskirk`, labels,
  milestone, Estate board **#17**), the `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
  trailer, the AgentGate `dangerous_patterns`-fires-in-prose quirk, the `brett-buskirk`-must-be-the-
  active-gh-account gotcha, the pack, and the estate memory.

Everything below is Edda-specific.

## What Edda is

`edda` is a single-file CLI for a **personal vault of markdown notes**. Named for the Norse Eddas —
the written codices where the myths themselves were finally set down — it is the tool where *you*
write things down. Notes are `.md` files in one flat vault; labels are frontmatter tags, not folders.

It is a **third archetype** in the collection, and the CLAUDE.md should keep it in its lane:

- the **pack** (huginn/muninn/geri/freki/grimnir) is **estate-scoped** — it scans every repo under one
  root and leans on `gh`/`jq`.
- **vegtam** is **current-repo-scoped** — zero config, goes anywhere, reads the repo you're standing in.
- **edda** is **personal-vault-scoped** — self-contained like vegtam, but *stateful*: it owns a vault
  and a config, and it is **fully offline**. No `gh`, no network, ever.

## The governing design decision — never violate

Edda's whole surface mutates **one directory the user cares about deeply** — their notes. That sets
the risk posture, and four invariants follow. They are not negotiable:

1. **The vault is sacred, and bounded.** Every write lands **inside `$EDDA_VAULT`** and nowhere else.
   `edda` never writes outside the vault, never phones home, never reads the wider filesystem for
   anything but the note the user named.
2. **Never hard-delete.** `rm` **soft-deletes to `$EDDA_VAULT/.trash/`** — confirm interactively or
   `--force`. There is no code path in edda that calls `rm -f` on a note. The `freki` reaper instinct
   is *wrong* here; the user's prose is not cruft.
3. **Edda is not a markdown/YAML engine.** It reads and writes its **own closed frontmatter schema**
   (`title` / `created` / `updated` / `labels`) with `sed`/`awk`. Do not pull a YAML library; do not
   try to parse arbitrary YAML. The schema is fixed and small on purpose.
4. **Verbs are a closed set.** The grammar is verb-first; the bareword fast-path is the *only* place a
   non-verb is accepted, and only when it names a note that already exists. Never let free text into
   the first dispatch position.

## The locked design decisions (build to these)

1. **Grammar — verb-first, with a bareword fast-path.**
   `edda new mynote`, `edda edit mynote`, `edda add mynote '…'`, `edda read mynote`, `edda list`,
   `edda search`, `edda path mynote`, `edda init`. Then: `edda mynote` (no verb) → **if a note named
   `mynote` exists, read it; else print help / a clean error.** The fast-path fires only on an existing
   note; verbs always win the first position.
2. **Vault + config — `env > file > default`, the muninn ladder.**
   `EDDA_VAULT` env > `${EDDA_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/edda/config}` (a sourced shell
   file) > default `${XDG_DATA_HOME:-$HOME/.local/share}/edda`. `edda init` scaffolds the vault (+
   `.trash/`) and writes a starter config. README nudges the user to point `EDDA_VAULT` at a synced /
   versioned dir — the vault is Terraform state for the brain; treat it like an artifact with a backup
   story.
3. **`add` — plain append by default; `-t/--timestamp` for a journal bullet.**
   Bare `add` appends the line as-is (with sane blank-line handling so paragraphs don't run together).
   `-t` prepends a `- <ISO-8601> — ` bullet. A lone `-` argument reads the line(s) from **stdin**
   (`echo … | edda add mynote -`) — and must not hang on a tty when there's no pipe.
4. **Renderer — `glow` optional, degrade gracefully.**
   `read` renders through the first available of `glow -s auto → bat -l md → a minimal awk render →
   cat`. Long notes pipe through `$PAGER` (`less -R`), with `--no-pager`. `--raw` dumps source.
   **Pipe-safe:** when stdout isn't a TTY or `NO_COLOR` is set, escapes collapse to empty and `read`
   emits plain markdown so it composes downstream.

## The script, at a glance

One file, `set -uo pipefail`, `SC2059` disabled file-level (the color-in-format idiom). Read
top→bottom:

- **Header** — the Norse framing + a usage synopsis + the dependency/offline note.
- **`VERSION`** — currently `0.1.0`. (No `SELF`/`HERE`: edda doesn't use them, and unused vars trip
  `shellcheck` — vegtam, the closest archetype, omits them too.)
- **Config/vault resolution** — the `env > config file > default` ladder: capture the `EDDA_VAULT`
  env override *before* sourcing `$CONFIG` (so env always wins), source the config, then resolve
  `_env_VAULT` > `EDDA_VAULT` (from the file) > `$DEFAULT_VAULT`. Sets `VAULT` and `TRASH`.
- **Palette** — TTY + `NO_COLOR` aware; escapes collapse to empty when piped. (Only the colors edda
  uses — no unused `M`, again for a clean `shellcheck`.)
- **Small helpers** — `have` · `is_help` · `note` · `now_iso` · `age_short` (ISO-string variant,
  prints `?` on unparseable) · `slugify` (ASCII-only, collapses punctuation, trims dashes, empty on
  all-punctuation) · `note_file` (name→path) · `fm_get` / `fm_set` (anchored to the **leading**
  `---…---` block only — a body `---` is never mistaken for frontmatter; `fm_set` rewrites through a
  vault-local temp + atomic rename) · `note_body` (strips frontmatter for rendering) · `note_labels`
  / `fmt_labels` (read/write the closed `labels:` list) · `open_editor` (`$VISUAL`→`$EDITOR`→nano→vi)
  · `ensure_vault`.
- **`cmd_*` functions** — `cmd_init` · `cmd_new` · `cmd_edit` · `cmd_add` (+ `append_to_note`, the
  blank-line/bullet-stacking logic) · `cmd_read` (+ `render_note` / `render_min`, the render ladder)
  · `cmd_list` · `cmd_labels` (+ `labels_overview` — vault-wide counts, or view/edit one note's tags)
  · `cmd_search` · `cmd_path` · `cmd_rm` (+ `confirm`, vegtam's `/dev/tty` gate — the
  soft-delete: `mv` into `.trash/`, never a hard delete). Each guards `is_help` first, then a
  while-loop `case` parses args; note-touching commands call `ensure_vault`.
- **`help_*` block** then **`cmd_help`** — two-level help (`edda help`, `edda <cmd> help`).
- **The `case` dispatcher** — verbs win the first position; the **bareword fast-path is the default
  arm** (reads a note only when one by that name exists, else a clean error + the menu).

Surface: **`new` · `edit` · `add` · `rm` · `read` · `list`/`ls` · `labels`/`label` · `search`/`grep`
· `path` · `init`**, plus `help` / `version`. `rm` (v0.2.0) soft-deletes to `.trash/` — the contract
above; `labels` (v0.3.0) lists usage counts and edits a note's tags in place. Still **ROADMAP**:
`mv`/`rename`, `open`, `export`, `daily`, `template`, links/backlinks.

**A note on `add` and dash-leading text.** Every `cmd_*` treats a `-*` token as an option (the house
convention), so text that *starts* with a dash — a literal `-` bullet, a `---` rule — needs the `--`
escape: `edda add ideas -- "---"`. A lone `-` right after the note name means stdin. This keeps the
frontmatter-vs-horizontal-rule gotcha honest: the `---` reaches the body via `--`, and `fm_get` still
reads only the leading block.

## Invariants specific to Edda

- **Self-contained & zero estate-deps.** No `$HUGINN_*`, no `repos()`, no `exemptions.json`, no
  sibling-directory scanning. It must stay `curl`-one-file-into-`~/.local/bin`-and-run, like vegtam.
- **Offline, always.** No `gh`, no `curl`, no network calls of any kind. If a feature seems to want
  the network, it's the wrong feature for edda.
- **Editor delegation only.** `edit` opens `$VISUAL` → `$EDITOR` → `nano` → `vi`. No custom editor —
  quick capture is `add`'s job, not a bespoke TUI's.
- **`search` degrades.** `rg` if present, else `grep -r`. Same `have`-gated pattern as the pack's
  optional tools.
- **Slugs are the ID.** Filename slug (`my-note.md`) is what the user types; frontmatter `title:` is
  the human string. Keep them decoupled.

## Gotchas (write a test for each)

- **Frontmatter vs. horizontal rule.** A note body can contain its own `---` lines. `fm_get` must
  treat **only the leading `---…---` block** as frontmatter, or it will swallow body content. Anchor
  the parse to the top of the file.
- **`slugify` is not just lowercase-and-dash.** Collapse punctuation and repeated separators, trim
  leading/trailing dashes, decide a non-ASCII policy, and **reject an empty result** rather than
  create `.md`. On collision (`my-note` exists), pick one behavior — refuse, or suffix `-2` — and hold
  it consistent.
- **Pipe-safety hides regressions.** A test must assert **zero escape bytes** when `read`/`list` is
  piped or `NO_COLOR` is set; otherwise a stray color leak passes silently.
- **`/dev/tty` can exist yet not be openable** (sandboxes). Reuse vegtam's `confirm()` spine — probe
  with `{ : < /dev/tty; }`, never leave `reply` unset under `set -u`. That's `rm`'s safety gate.
- **`add -` (stdin) must detect a pipe.** Guard the stdin read so it doesn't block on an interactive
  tty when nothing is piped in.
- **shellcheck `SC2059`** (vars in a printf format string) is disabled file-level on purpose — the
  color-escapes-in-format idiom, matching the pack. Keep the script otherwise shellcheck-clean.

## Editing & shipping

- Every change must be `bash -n edda` + `shellcheck edda` clean. **Add the missing CI gate:** the
  scaffold wires AgentGate but not the `.github/workflows/shellcheck.yml` the rest of the pack runs on
  every push/PR — port it from `vegtam`/`huginn` as the first infra PR.
- **Test the way the pack is tested:** a throwaway vault (`EDDA_VAULT="$(mktemp -d)"`) for creation +
  frontmatter + label filtering + `add`/`-t` + slug edge cases + `rm`-lands-in-`.trash`; `NO_COLOR` /
  piped output (zero escapes); and the render fallback with `glow`/`bat` hidden from `PATH`.
- Bump `VERSION`; keep `README` / `CHANGELOG` / `ROADMAP` in sync with the change. After a PR merges,
  refresh Brett's installed copy: `install -m 0755 edda ~/.local/bin/edda`.

## Status

**v0.3.0 — v1 surface + `rm` + `labels`, shipped.** The `edda` script implements
`init`/`new`/`edit`/`add`/`rm`/`read`/`list`/`labels`/`search`/`path` + `help`/`version` behind the
locked decisions above; `bash -n` + `shellcheck` clean. `rm` soft-deletes to `.trash/` via the
`confirm()` `/dev/tty` gate (or `--force`), never a hard delete; `labels` lists vault-wide usage
counts and edits a note's tags in place. CI runs `.github/workflows/shellcheck.yml`
(the `bash -n` + `shellcheck` gate) and `.github/workflows/test.yml` (the `test/run.sh` throwaway-
vault harness, 83 assertions). AgentGate still wired (`scope` → warning, `secrets` +
`dangerous_patterns` → error); edda's own code trips none of the default denylist patterns. **Do
not spell those code tokens out in a committed file** — the rule scans added diff lines including
prose, so naming them here would block the PR (the estate-manual quirk). Adding CI workflows also
raises a `scope` warning (they're a denied path), and a first-cut PR this size raises a `diff_size`
warning; both are non-blocking and expected. Docs written for adoption.

Next milestone: **`mv`/`rename`** (re-slug a note and update its `title:`, keeping slug and title in
sync), then `open` — see `ROADMAP.md`. macOS `date` portability (dropping the GNU-coreutils caveat)
is a separate, still-open item.

## Reference

- `~/github-repos/vegtam/vegtam` — dispatcher / two-level help / palette / the `confirm()` dry-run
  spine that `rm` borrows / the terse, lightly-wry voice.
- `~/github-repos/muninn/muninn` — the `env > config > default` resolution ladder, hand-rolled
  metadata parsing (don't reach for `jq`/YAML), and `age_short` / `since_to_gitdate` helpers to lift.
- `~/github-repos/huginn/huginn` — the origin of the house voice and status-line rendering.
