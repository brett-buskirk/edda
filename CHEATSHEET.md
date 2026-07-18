# edda cheat sheet

Quick reference for every command, option, and behavior. `edda` is a single self-contained Bash
script for a **personal vault of markdown notes** — one flat directory of `.md` files, labelled by
frontmatter tags, **fully offline**.

For the narrative version see the [README](README.md); for per-command detail in the terminal, run
`edda <command> help`.

---

## At a glance

| Command | Aliases | What it does | Options |
|---------|---------|--------------|---------|
| [`new`](#new) | | Create a note | `-l`/`--label`, `-e`/`--edit` |
| [`edit`](#edit) | | Open a note in `$EDITOR` | |
| [`add`](#add) | | Append a line to a note | `-t`/`--timestamp`, `-` (stdin), `--` (escape) |
| [`rm`](#rm) | | Soft-delete a note to `.trash/` | `-f`/`--force` |
| [`mv`](#mv) | `rename` | Rename a note — re-slug + retitle | |
| [`read`](#read) | | Render a note | `--raw`, `--no-pager` |
| [`list`](#list) | `ls` | List notes, newest first | `-l`/`--label` |
| [`labels`](#labels) | `label` | Labels in use + counts, or edit a note's | `-a`/`--add`, `-r`/`--remove` |
| [`search`](#search) | `grep` | Search note contents | |
| [`path`](#path) | | Print a note's file path | |
| [`backup`](#backup) | `archive` | Archive the vault to a `.tar.gz` (offline) | *(dest: dir / file / `-`)* |
| [`init`](#init) | | Scaffold the vault + a starter config | `-f`/`--force` |
| [`<note>`](#the-bareword-fast-path) | | *(no verb)* read a note by that name | |
| [`help`](#help--version) | `-h`, `--help` | The command menu | |
| `version` | `-V`, `--version` | Print the version | |

- **Write** commands (`new` `edit` `add` `rm` `mv`) create or change notes — and `rm` only ever
  *soft-deletes* (to `.trash/`). **Read** commands (`read` `list` `search` `path`) never change
  anything; `labels` reads by default and only writes a note when given `-a`/`-r`.
- The grammar is **verb-first**. `edda <note>` with no verb reads the note — but only when a note by
  that name already exists; otherwise you get a clean error and the menu.
- Running `edda` with no arguments prints the help menu.

---

## Requirements & global behavior

- **Requires** `bash` + **GNU** coreutils (`awk`, `sed`, and GNU `date` — the timestamps use `date
  -d`/`%:z`). Linux and WSL/Git Bash have these built in; on macOS, `brew install coreutils` and put
  them on your `PATH`. Everything else is optional and degrades gracefully:
  - [`glow`](https://github.com/charmbracelet/glow) or [`bat`](https://github.com/sharkdp/bat)
    pretty-render `read` (else a minimal built-in render, else `cat`).
  - [`rg`](https://github.com/BurntSushi/ripgrep) speeds up `search` (else `grep -r`).
- **Offline, always.** No `gh`, no `curl`, no network calls of any kind.
- **`NO_COLOR`** — set it (`NO_COLOR=1 edda …`) to disable color. Output is also automatically plain
  when piped or redirected (not a TTY). `read`/`list`/`search`/`path` emit **zero escape codes** when
  piped, so they compose cleanly downstream.
- **Two-level help** — `edda help` for the menu, `edda <command> help` (or `-h`/`--help`) for one
  command.
- **Exit codes** — `0` on success; `1` on error (no vault, missing note, empty/duplicate slug, empty
  `add` text, an unknown command or a bareword that names no note, or a usage error).

### The vault, and how it's found

Every note lives in one flat directory — the **vault** — resolved with the same ladder every command
uses, **env > config file > default**:

| Priority | Source | Value |
|----------|--------|-------|
| 1 | `EDDA_VAULT` in the environment | whatever you export |
| 2 | `EDDA_VAULT` in the config file | `$EDDA_CONFIG`, default `${XDG_CONFIG_HOME:-~/.config}/edda/config` (a sourced shell file) |
| 3 | the default | `${XDG_DATA_HOME:-~/.local/share}/edda` |

Point `EDDA_VAULT` at a synced or version-controlled directory and the vault travels with you.

### Environment variables

| Variable | Effect |
|----------|--------|
| `EDDA_VAULT` | The vault directory (highest priority). |
| `EDDA_CONFIG` | Path to the config file (default `${XDG_CONFIG_HOME:-~/.config}/edda/config`). |
| `XDG_CONFIG_HOME` / `XDG_DATA_HOME` | Feed the config-path and default-vault fallbacks. |
| `VISUAL` → `EDITOR` | Which editor `edit` (and `new -e`) opens; may include flags (`code --wait`). Falls back to `nano` → `vi`. |
| `PAGER` | Pager for long `read` output (default `less -R`). |
| `NO_COLOR` | Any value disables color. |

### The frontmatter schema

Every note opens with the same small, fixed block — the whole schema, on purpose. Only the
**leading** `---…---` block is frontmatter; a `---` rule later in your prose is left untouched.

```markdown
---
title: Kickoff notes
created: 2026-07-18T14:05:55-04:00
updated: 2026-07-18T14:05:56-04:00
labels: [work, urgent]
---

# Kickoff notes
```

### Slugs (the note id)

The **slug** is the filename (`my-note.md`) and the id you type; the frontmatter `title:` is the human
string — the two stay decoupled. Slugs are lowercased, with every run of non-`[a-z0-9]` folded to a
single dash and leading/trailing dashes trimmed (an ASCII-only policy). An all-punctuation title has
no slug and is refused; a name that already exists is refused rather than clobbered. Commands that
take a note name slugify it defensively, so `edda read "My Note"` finds `my-note.md`.

---

## Write

### `new`

Create a note. The title becomes both the filename slug and the frontmatter `title:`.

```sh
edda new "Reading list"                  # → reading-list.md, title "Reading list"
edda new -l work -l urgent "Retro prep"  # seed labels (repeatable)
edda new -e "Draft post"                 # create, then open it in your editor
```

| Option | Effect |
|--------|--------|
| `-l`, `--label <label>` | Add a label to the new note (repeatable). Labels are slugified. |
| `-e`, `--edit` | Open the new note in your editor after creating it. |

Flags come **before** the title; the rest of the line is the title verbatim. Refuses on an empty slug
or a name that already exists (exit 1).

### `edit`

Open a note in your editor — `$VISUAL` → `$EDITOR` → `nano` → `vi`. Bumps the frontmatter `updated:`
timestamp, but only if you actually changed the file.

```sh
edda edit reading-list
```

A multi-word `$EDITOR` (e.g. `code --wait`, `emacsclient -t`) is split into its command + flags.

### `add`

Append a line to a note.

```sh
edda add reading-list "Gödel, Escher, Bach"   # plain append (paragraph-spaced)
edda add standup -t "shipped the parser"       # a timestamped journal bullet
echo "quick thought" | edda add ideas -        # read the line from stdin
edda add notes -- "-> a line starting with a dash"   # -- escapes dash-leading text
```

| Option | Effect |
|--------|--------|
| `-t`, `--timestamp` | Prepend a `- <ISO-8601> — ` bullet. Consecutive `-t` adds stack into one list — a running journal. |
| `-` | A lone dash (after the note name) reads the text from **stdin**. Refuses — rather than hangs — when nothing is piped in. |
| `--` | End-of-options: everything after it is literal text. Needed for text that **starts** with a dash (a `- bullet`, a `---` rule). |

Plain `add` separates the new line from prior content with one blank line so paragraphs don't run
together. The note's `updated:` is bumped on every add.

### `rm`

**Soft-delete** a note — it moves to `$EDDA_VAULT/.trash/`, never an unrecoverable delete. There is
no code path in edda that hard-deletes your prose.

```sh
edda rm old-draft          # confirms, then moves it to .trash/
edda rm old-draft --force  # skip the prompt
```

| Option | Effect |
|--------|--------|
| `-f`, `--force` | Skip the confirmation prompt. |

The confirmation reads `/dev/tty` directly, so a piped/redirected stdin can't silently auto-confirm —
pass `--force` for that. A second delete of the same name is timestamp-suffixed in `.trash/`, never
clobbered. Restore anytime by moving the file back out of `.trash/`:
`mv "$EDDA_VAULT/.trash/old-draft.md" "$EDDA_VAULT/"`.

### `mv`

Rename a note (alias: `rename`). The new name becomes **both** the filename slug and the frontmatter
`title:`, kept in sync; `created` and the body are untouched.

```sh
edda mv reading-list "Books to read"   # → books-to-read.md, title "Books to read"
edda rename books-to-read "Reading"    # alias
```

- If the new name slugs to the **same** filename, only the `title:` changes (fix wording/case in place).
- **Never overwrites** a different existing note — `rm` (or rename) that one first.
- Refuses (rc 1) on a missing source note or a new name that has no sluggable characters.

---

## Read

### `read`

Render a note — `glow` → `bat` → a minimal built-in render → `cat`, whichever is present. Long notes
page through `$PAGER`.

```sh
edda read reading-list          # rendered
edda read reading-list --raw    # the source, frontmatter and all
edda read reading-list --no-pager
edda reading-list               # same as read, via the bareword fast-path
```

| Option | Effect |
|--------|--------|
| `--raw` | Dump the source verbatim (frontmatter included) — for piping/scripting. |
| `--no-pager` | Never page, even when the note is long. |

Piped or under `NO_COLOR`, `read` emits **plain markdown with zero escape codes** (frontmatter
stripped), so it composes downstream.

### `list`

List notes, newest `updated` first: slug · title · age · labels.

```sh
edda list                # every note
edda ls                  # alias
edda list -l work        # filter to one label
edda list work           # positional shorthand for the same filter
```

| Option | Effect |
|--------|--------|
| `-l`, `--label <label>` | Show only notes carrying that label (a bare positional works too). |

### `labels`

With no note, list every label in use across the vault, by descending count. Given a `<note>`, show
its labels — or edit them with `-a`/`-r`, which rewrite the closed `labels:` field in place.

```sh
edda labels                                 # every label in use + counts
edda labels retro-prep                      # one note's labels
edda labels retro-prep -a urgent -r draft   # add 'urgent', remove 'draft'
```

| Option | Effect |
|--------|--------|
| `-a`, `--add <label>` | Add a label to the note (repeatable). |
| `-r`, `--remove <label>` | Remove a label from the note (repeatable). |

Labels are slugified; adding a duplicate or removing an absent label is a no-op, and editing bumps the
note's `updated:`.

### `search`

Search note contents across the vault (the `.trash/` is skipped). Uses `rg` when present, else
`grep -r`. Matching is **case-insensitive** and the pattern is a **regex**, either way — `rg` applies
smart-case, so an uppercase letter in the pattern makes it case-sensitive.

```sh
edda search parser
edda grep "TODO|FIXME"   # alias; alternation works under both engines
```

A run with no matches prints a dim note and still exits `0` (not an error).

### `path`

Print a note's file path — plain, so it scripts cleanly.

```sh
edda path todo
vim "$(edda path todo)"          # open it in an editor
cat "$(edda path todo)"          # or feed it to anything
```

Exits non-zero (message to **stderr**) when the note doesn't exist, so `$(edda path …)` fails loudly
in a script.

---

## Setup

### `init`

Scaffold the vault (and its `.trash/`, where `rm` soft-deletes) and write a starter config.
Idempotent — safe to run again.

```sh
edda init
edda init --force        # overwrite an existing config
```

| Option | Effect |
|--------|--------|
| `-f`, `--force` | Overwrite an existing config file. |

Scaffolds whichever vault the resolution ladder points at, and writes the config to `$EDDA_CONFIG`.

### `backup`

Archive the whole vault to a timestamped `.tar.gz` (alias: `archive`). edda's one write *outside* the
vault — and it **never uploads anything itself**; getting the archive to the cloud is a separate
tool's job (a Drive-synced folder, `rclone`, cron). Extract with `tar -xzf`.

```sh
edda backup                    # → ./edda-backup-<timestamp>.tar.gz
edda backup ~/Drive/edda/      # into a directory (e.g. a cloud-synced folder)
edda backup ~/backups/snap.tar.gz   # to an exact path
edda backup -                  # stream the archive to stdout
```

| Destination | Result |
|-------------|--------|
| *(none)* | `./edda-backup-<timestamp>.tar.gz` in the current directory |
| `<dir>` | the timestamped archive written into `<dir>` |
| `<file>` | written to exactly that path |
| `-` | the archive streamed to **stdout** (pipe it) |

Never writes the archive **inside** the vault (refuses, rc 1), and errors on a missing destination
directory. Upload recipes:

```sh
edda backup - | rclone rcat gdrive:edda-backups/vault-$(date +%F).tar.gz
edda backup ~/backups/ && rclone copy ~/backups/ gdrive:edda-backups/
# nightly cron: 0 2 * * *  edda backup "$HOME/Google Drive/edda-backups/"
```

### The bareword fast-path

With no verb, `edda <note>` reads the note — **only** when a note by that name already exists.
Verbs always win the first position, and an unknown word that names no note gives a clean error plus
the menu (exit 1), never free-text guessing.

```sh
edda reading-list        # ≡ edda read reading-list  (if reading-list.md exists)
edda not-a-note          # error + menu, exit 1
```

---

## `help` & version

```sh
edda help              # the command menu
edda -h                # same
edda <command> help    # detail for one command (e.g. edda add help)
edda --version         # print the version
edda -V                # same
```

---

## Recipes

```sh
# First-time setup — scaffold the vault, then point EDDA_VAULT at a synced dir
edda init
export EDDA_VAULT="$HOME/Notes"   # e.g. a Syncthing/Dropbox/git-backed folder

# Capture a quick note and start writing
edda new -e "Meeting with the client"

# Keep a running standup / journal — timestamped bullets stack into one list
edda add standup -t "reviewed the PR queue"
edda add standup -t "shipped edda v1"

# Pipe something in from another command
git log --oneline -5 | edda add release-notes -

# Read a note fast (no verb needed)
edda reading-list

# What have I got, and what's tagged 'work'?
edda list
edda list work

# Find that thing I wrote down
edda search "postgres"

# Open a note in your editor by path, or feed it to another tool
vim "$(edda path todo)"
pandoc "$(edda path essay)" -o essay.pdf

# Plain output for a pipe or a log (no color, zero escapes)
NO_COLOR=1 edda list
edda read todo | grep -i urgent
```
