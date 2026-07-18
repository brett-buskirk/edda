# edda

[![Shellcheck](https://github.com/brett-buskirk/edda/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/brett-buskirk/edda/actions/workflows/shellcheck.yml)
[![Test](https://github.com/brett-buskirk/edda/actions/workflows/test.yml/badge.svg)](https://github.com/brett-buskirk/edda/actions/workflows/test.yml)

**A pocket CLI for your personal vault of markdown notes.**

The Norse *Eddas* are the codices where the old myths were finally written down. `edda` is the tool
where *you* write things down: notes are plain `.md` files in one flat **vault**, labelled by
frontmatter tags — no folders, no database, and **no network, ever**. It's a single self-contained
Bash script. Drop it on your `PATH` and start capturing.

```sh
edda new "Kickoff notes"          # create a note
edda add kickoff-notes -t "call with the client went well"
edda kickoff-notes                # read it (no verb needed)
edda list                         # what have I got?
edda search client                # grep the whole vault
```

## The vault is sacred

`edda`'s entire surface mutates one directory you care about deeply — your notes. That sets the risk
posture, and four rules hold throughout. They are not negotiable:

- **Every write lands inside the vault.** `edda` never writes outside `$EDDA_VAULT`, never reads the
  wider filesystem for anything but the note you named, and never phones home.
- **Nothing is ever hard-deleted.** `edda rm` soft-deletes to `$EDDA_VAULT/.trash/` — never an
  unrecoverable delete of your prose. Restore a note by moving it back out.
- **A small, closed frontmatter schema.** Just `title` / `created` / `updated` / `labels`, read and
  written with `sed`/`awk`. `edda` is a note tool, not a general YAML engine.
- **Offline, always.** No `gh`, no `curl`, no network calls of any kind.

Point `EDDA_VAULT` at a synced or version-controlled directory and the vault travels with you — it's
state worth backing up, so treat it like an artifact with a backup story.

## Install

`edda` is a single, self-contained Bash script — **curl it straight onto your `PATH`:**

```sh
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/brett-buskirk/edda/main/edda -o ~/.local/bin/edda
chmod +x ~/.local/bin/edda
```

(Make sure `~/.local/bin` is on your `PATH`.) Then scaffold your vault:

```sh
edda init
```

**Requires** `bash` and **GNU** coreutils — the timestamps use GNU `date` (`-d`, `%:z`). Linux and
WSL/Git Bash on Windows have these built in; on macOS, install GNU coreutils (`brew install
coreutils`) and put them on your `PATH`. Everything else is optional and degrades gracefully:
[`glow`](https://github.com/charmbracelet/glow) or [`bat`](https://github.com/sharkdp/bat)
pretty-render `read` (else a plain fallback), and [`rg`](https://github.com/BurntSushi/ripgrep)
speeds up `search` (else `grep`).

## Usage

```
edda new <title…>          create a note (-l label, -e to open your editor)
edda edit <note>           open a note in $EDITOR
edda add <note> [-t] '…'   append a line (-t timestamps it; '-' reads stdin)
edda rm <note>             soft-delete a note to .trash/ (--force to skip confirm)
edda read <note>           render a note (--raw for source)
edda list [-l label]       list notes, newest first (alias: ls)
edda search <pattern>      grep the vault (alias: grep)
edda path <note>           print a note's file path
edda init                  scaffold the vault + a starter config
edda <note>                no verb → read that note, if it exists
edda help                  the menu
edda <cmd> help            detail & options for any command
edda version               print the version
```

For a one-page reference to every command, option, and behavior, see the
[**cheat sheet**](CHEATSHEET.md).

The grammar is **verb-first**. The one exception is the bareword fast-path: `edda <note>` with no
verb reads the note — but *only* when a note by that name already exists; otherwise you get a clean
error and the menu. Verbs always win the first position.

### `new` — capture a note

```sh
edda new "Reading list"                 # → reading-list.md, title "Reading list"
edda new -l work -l urgent "Retro prep" # seed labels
edda new -e "Draft post"                # create, then open in your editor
```

The title becomes both the filename **slug** (lowercased, punctuation folded to dashes) and the
frontmatter `title:` — the two stay decoupled, so the slug is the id you type and the title is the
human string. `edda` refuses to clobber an existing note.

### `add` — the fast path for capture

```sh
edda add reading-list "Gödel, Escher, Bach"      # plain append (paragraph-spaced)
edda add standup -t "shipped the parser"          # a timestamped journal bullet
echo "quick thought" | edda add ideas -           # read the line from stdin
```

Plain `add` appends the line as a paragraph, with a blank line so paragraphs don't run together.
`-t` prepends a `- <ISO-8601> — ` bullet, and consecutive timestamped adds stack into one list — a
running journal. A lone `-` reads from stdin (and refuses, rather than hangs, when nothing is piped).
Text that *starts* with a dash needs the `--` escape: `edda add ideas -- "-> arrow"`.

### `rm` — soft-delete, never a hard delete

```sh
edda rm old-draft          # confirms, then moves it to $EDDA_VAULT/.trash/
edda rm old-draft --force  # skip the prompt
```

`rm` **moves** the note into `$EDDA_VAULT/.trash/` — there is no code path in edda that
unrecoverably deletes your prose. It confirms once (reading `/dev/tty`, so a pipe can't
auto-confirm a batch) unless you pass `--force`; a second delete of the same name is
timestamp-suffixed rather than clobbered. Restore anytime by moving the file back out of `.trash/`.

### `read` — render it

```sh
edda read reading-list        # rendered via glow → bat → a built-in fallback
edda read reading-list --raw  # the source, frontmatter and all
edda reading-list             # same as 'read', via the bareword fast-path
```

Long notes page through `$PAGER` (`--no-pager` to skip). Piped or under `NO_COLOR`, `read` emits
plain markdown with zero escape codes, so it composes cleanly downstream.

### `list` / `search` / `path`

```sh
edda list                # every note, newest 'updated' first: slug · title · age · labels
edda list -l work        # filter to one label (or the shorthand: edda list work)
edda search parser       # search contents across the vault (.trash/ is skipped)
vim "$(edda path todo)"  # print a note's path — plain, so it scripts cleanly
```

### `init` & configuration

`edda init` scaffolds the vault (and its `.trash/`) and writes a starter config. The vault is
resolved with the same ladder every command uses — **env > config file > default:**

1. `$EDDA_VAULT` in the environment, else
2. `EDDA_VAULT` set in the config file (`$EDDA_CONFIG`, default
   `${XDG_CONFIG_HOME:-~/.config}/edda/config` — a plain sourced shell file), else
3. the default `${XDG_DATA_HOME:-~/.local/share}/edda`.

### The frontmatter schema

Every note opens with the same small, fixed block — the whole schema, on purpose:

```markdown
---
title: Kickoff notes
created: 2026-07-18T14:05:55-04:00
updated: 2026-07-18T14:05:56-04:00
labels: [work, urgent]
---

# Kickoff notes
```

Only the *leading* block is frontmatter — a `---` horizontal rule later in your prose is left
untouched.

## Status

**v0.2.0** — the v1 verb surface (`new` · `edit` · `add` · `read` · `list` · `search` · `path` ·
`init`) plus `rm` (soft-delete to `.trash/`), two-level help, a pipe-safe palette, and `shellcheck`-
and test-gated CI, in one self-contained script. See [ROADMAP.md](ROADMAP.md) for what's next
(`labels`, `mv`/`rename`, and more) and [CHANGELOG.md](CHANGELOG.md) for the record.

## License

MIT — see [LICENSE](LICENSE).
