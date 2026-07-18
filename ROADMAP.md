# Roadmap

_What's planned for edda — check items off as they ship. Each phase is a version milestone and a
focused PR._

## Shipped
- [x] **v0.1.0 — the v1 verb surface** · one self-contained script built to the locked design:
  `init` · `new` · `edit` · `add` (plain / `-t` timestamp / `-` stdin) · `read` (glow → bat →
  minimal → cat, pipe-safe) · `list`/`ls` (with label filtering) · `search`/`grep` · `path`. The
  `env > config > default` vault ladder, the closed frontmatter schema, verb-first grammar with the
  bareword fast-path, two-level help, a `NO_COLOR`/non-TTY-aware palette, the `shellcheck` CI gate,
  and a throwaway-vault test harness.

## Next
- [ ] **`rm` — with the soft-delete contract** · `edda rm <note>` moves the file to
  `$EDDA_VAULT/.trash/` (never a hard delete), confirming interactively (the `confirm()` `/dev/tty`
  spine) or with `--force`. The one destructive-adjacent verb, and it ships only this way.
- [ ] **`labels`** · list every label in use with counts; add/remove labels on a note (rewriting the
  closed `labels:` field in place, no YAML library).
- [ ] **`mv` / `rename`** · re-slug a note and update its `title:`, keeping slug and title in sync.
- [ ] **`open`** · hand a note to the OS opener (respecting the offline, editor-delegation posture).

## Maybe someday (nice-to-have, not planned)
- `daily` / `template` — scaffold a note from a template or a dated journal entry.
- `export` — render a note (or the vault) to HTML/PDF via an external renderer, still offline.
- Links & backlinks between notes (`[[wikilink]]`-style), and a `path`-driven completion helper.

## Out of scope (by design)
These aren't backlog — they're deliberately not what edda is for.

- **Anything networked.** No `gh`, no `curl`, no sync-over-the-wire. The vault is a plain directory;
  point `EDDA_VAULT` at a synced/versioned dir and let that tool own the network.
- **A general YAML/markdown engine.** The frontmatter schema is small and closed on purpose; edda
  will not grow arbitrary-YAML parsing.
- **A bespoke TUI editor.** Editing delegates to `$VISUAL`/`$EDITOR`; quick capture is `add`'s job.
- **Any hard delete of a note.** There is no code path that unrecoverably removes your prose.
