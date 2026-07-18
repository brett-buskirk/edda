#!/usr/bin/env bash
# edda test harness — a self-contained bash runner (no bats dependency), the way
# the pack is tested: throwaway vaults (EDDA_VAULT="$(mktemp -d)") exercising the
# v1 surface end to end. Exits non-zero if any assertion fails.
#
#   bash test/run.sh            # run against ../edda
#   EDDA_BIN=/path/to/edda bash test/run.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
EDDA="${EDDA_BIN:-$HERE/../edda}"
ESC=$'\x1b'

PASS=0; FAIL=0
declare -a TMPDIRS=()
cleanup(){ local d; for d in "${TMPDIRS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

mkd(){ local d; d="$(mktemp -d)"; TMPDIRS+=("$d"); printf '%s' "$d"; }

# A fresh, isolated vault + config for a test. Keeps EDDA_CONFIG out of ~/.config.
fresh(){
  EDDA_VAULT="$(mkd)"; export EDDA_VAULT
  EDDA_CONFIG="$(mkd)/config"; export EDDA_CONFIG
  unset XDG_DATA_HOME XDG_CONFIG_HOME
}

pass(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
fail(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '         %s\n' "$2"; }
skip(){ printf '  skip %s%s\n' "$1" "${2:+  ($2)}"; }

assert_eq(){       if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi; }
assert_rc(){       if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected rc $2, got $3"; fi; }
assert_contains(){ case "$2" in *"$3"*) pass "$1";; *) fail "$1" "[$2] lacks [$3]";; esac; }
assert_missing(){  case "$2" in *"$3"*) fail "$1" "[$2] unexpectedly contains [$3]";; *) pass "$1";; esac; }
assert_file(){     if [ -f "$2" ]; then pass "$1"; else fail "$1" "no such file: $2"; fi; }
assert_no_esc(){   if printf '%s' "$2" | grep -q "$ESC"; then fail "$1" "output carries ANSI escapes"; else pass "$1"; fi; }

# A PATH of the everyday tools, resolved with `type -P` so a shell alias (e.g. a
# distro's `grep --color`) can't poison the symlink target. `omit` is a space-list
# of tools to leave out, to force a degraded path (no glow/bat, or no rg).
shim_path(){
  local omit=" ${1:-} " d t p; d="$(mkd)"
  for t in bash sh awk sed grep cat date mktemp mv rm cp ln basename dirname \
           tput wc sort head tail printf env readlink chmod mkdir ls tr od less rg glow bat; do
    case "$omit" in *" $t "*) continue;; esac
    p="$(type -P "$t" 2>/dev/null)" && ln -sf "$p" "$d/$t"
  done
  printf '%s' "$d"
}

# A throwaway editor script that appends a marker to the file it is handed (the
# last argv element, so it works whether invoked as `ed FILE` or `ed --flag FILE`).
make_editor(){
  local d e; d="$(mkd)"; e="$d/fake-editor"
  # SC2016: the single-quoted body is written verbatim INTO the editor script — the
  # ${@: -1} must reach that script unexpanded, so single quotes are deliberate.
  # shellcheck disable=SC2016
  { printf '#!/usr/bin/env bash\n'; printf 'f="${@: -1}"; printf "edited by the fake editor\\n" >> "$f"\n'; } > "$e"
  chmod +x "$e"; printf '%s' "$e"
}

# ── init ───────────────────────────────────────────────────────────────────────
t_init(){
  fresh
  "$EDDA" init >/dev/null
  { [ -d "$EDDA_VAULT" ] && pass "init creates the vault dir"; } || fail "init creates the vault dir"
  { [ -d "$EDDA_VAULT/.trash" ] && pass "init creates .trash/"; } || fail "init creates .trash/"
  { [ -f "$EDDA_CONFIG" ] && pass "init writes a config"; } || fail "init writes a config"
  assert_contains "config points EDDA_VAULT at the vault" "$(cat "$EDDA_CONFIG")" "EDDA_VAULT=\"$EDDA_VAULT\""
}

# ── new + frontmatter schema ────────────────────────────────────────────────────
t_new_frontmatter(){
  fresh; "$EDDA" init >/dev/null
  "$EDDA" new "My First Note!" >/dev/null
  local f="$EDDA_VAULT/my-first-note.md"
  assert_file "new slugifies title → my-first-note.md" "$f"
  local body; body="$(cat "$f")"
  assert_contains "frontmatter has title"   "$body" "title: My First Note!"
  assert_contains "frontmatter has created" "$body" "created: "
  assert_contains "frontmatter has updated" "$body" "updated: "
  assert_contains "frontmatter has labels"  "$body" "labels: []"
  assert_contains "body has H1 heading"     "$body" "# My First Note!"
  # slug and title stay decoupled: the filename is the slug, title is the human string
  assert_eq "title decoupled from slug" "My First Note!" "$("$EDDA" read my-first-note --raw | sed -n 's/^title: //p')"
}

t_new_labels(){
  fresh; "$EDDA" init >/dev/null
  "$EDDA" new -l Work -l ideas "Tagged" >/dev/null
  assert_contains "labels seeded + slugified" "$(cat "$EDDA_VAULT/tagged.md")" "labels: [work, ideas]"
}

t_slug_edges(){
  fresh; "$EDDA" init >/dev/null
  "$EDDA" new "Café résumé" >/dev/null
  assert_file "non-ASCII folds to ASCII slug" "$EDDA_VAULT/caf-r-sum.md"
  local out rc
  out="$("$EDDA" new "!!!" 2>&1)"; rc=$?
  assert_rc "empty slug refused" 1 "$rc"
  assert_contains "empty slug message" "$out" "no slug-able characters"
  "$EDDA" new "Dup" >/dev/null
  out="$("$EDDA" new "Dup" 2>&1)"; rc=$?
  assert_rc "collision refused (no clobber)" 1 "$rc"
  assert_contains "collision message" "$out" "already exists"
}

# ── add: plain, -t, stacking, stdin ─────────────────────────────────────────────
t_add(){
  fresh; "$EDDA" init >/dev/null; "$EDDA" new "Journal" >/dev/null
  "$EDDA" add journal "First paragraph." >/dev/null
  local body; body="$(cat "$EDDA_VAULT/journal.md")"
  assert_contains "plain add appends text" "$body" "First paragraph."
  # a blank line separates the heading from the first paragraph
  assert_contains "blank-line separation" "$body" "# Journal"$'\n'$'\n'"First paragraph."

  "$EDDA" add -t journal "entry one" >/dev/null
  "$EDDA" add journal -t "entry two" >/dev/null
  body="$(cat "$EDDA_VAULT/journal.md")"
  assert_contains "-t makes a timestamped bullet" "$body" "— entry one"
  # two consecutive bullets stack contiguously (no blank line between them)
  local twobullets; twobullets="$(grep -A1 'entry one' "$EDDA_VAULT/journal.md" | tail -1)"
  assert_contains "-t bullets stack into a list" "$twobullets" "— entry two"

  printf 'from a pipe\n' | "$EDDA" add journal - >/dev/null
  assert_contains "add - reads stdin" "$(cat "$EDDA_VAULT/journal.md")" "from a pipe"

  # add - with an empty pipe must not hang and must report nothing to add
  local rc; : | "$EDDA" add journal - >/dev/null 2>&1; rc=$?
  assert_rc "add - with empty pipe reports nothing (no hang)" 1 "$rc"

  # 'updated' is bumped by add (differs from created after edits within the vault)
  assert_missing "add leaves no temp files behind" "$(ls -a "$EDDA_VAULT")" ".edda-tmp"
}

# ── edit: applies changes, bumps 'updated' only on change, splits multi-word EDITOR ─
t_edit(){
  fresh; "$EDDA" init >/dev/null; "$EDDA" new "Editable" >/dev/null
  local ed; ed="$(make_editor)"
  local u0 u1 u2
  u0="$("$EDDA" read editable --raw | sed -n 's/^updated: //p')"
  sleep 1
  EDITOR="$ed" "$EDDA" edit editable >/dev/null
  assert_contains "edit applies the editor's changes" "$(cat "$EDDA_VAULT/editable.md")" "edited by the fake editor"
  u1="$("$EDDA" read editable --raw | sed -n 's/^updated: //p')"
  if [ "$u0" != "$u1" ]; then pass "edit bumps updated on change"; else fail "edit bumps updated on change" "held at $u0"; fi

  sleep 1
  EDITOR=true "$EDDA" edit editable >/dev/null
  u2="$("$EDDA" read editable --raw | sed -n 's/^updated: //p')"
  assert_eq "no-change edit holds updated" "$u1" "$u2"

  # a multi-word $EDITOR ("cmd --flag") must be split into argv, not sought as one name
  fresh; "$EDDA" init >/dev/null; "$EDDA" new "Multi" >/dev/null
  EDITOR="$ed --wait" "$EDDA" edit multi >/dev/null
  assert_contains "multi-word EDITOR is split into argv" "$(cat "$EDDA_VAULT/multi.md")" "edited by the fake editor"
}

# ── rm: soft-delete to .trash/, the confirm gate, and no-clobber ─────────────────
t_rm(){
  fresh; "$EDDA" init >/dev/null; "$EDDA" new "Doomed" >/dev/null

  # --force soft-deletes: gone from the vault, present (and intact) in .trash/
  "$EDDA" rm doomed --force >/dev/null
  if [ -f "$EDDA_VAULT/doomed.md" ]; then fail "rm --force removes the note from the vault"
  else pass "rm --force removes the note from the vault"; fi
  assert_file "rm --force lands the note in .trash/" "$EDDA_VAULT/.trash/doomed.md"
  assert_contains "trashed note is intact (recoverable)" "$(cat "$EDDA_VAULT/.trash/doomed.md")" "# Doomed"

  # the /dev/tty safety gate: without --force and no usable terminal, it aborts and
  # the note stays. setsid detaches the controlling tty so this can't block on a real
  # terminal when the suite is run interactively.
  "$EDDA" new "Kept" >/dev/null
  if command -v setsid >/dev/null 2>&1; then
    local rc; setsid "$EDDA" rm kept </dev/null >/dev/null 2>&1; rc=$?
    assert_rc "rm without --force + no tty aborts (rc 0)" 0 "$rc"
    assert_file "rm safety gate leaves the note in place" "$EDDA_VAULT/kept.md"
  else
    skip "rm without --force + no tty aborts (rc 0)" "no setsid"
    skip "rm safety gate leaves the note in place" "no setsid"
  fi

  # missing note → rc 1
  local rc2; "$EDDA" rm ghost --force >/dev/null 2>&1; rc2=$?
  assert_rc "rm of a missing note is rc 1" 1 "$rc2"

  # never clobber: a second delete of the same name is timestamp-suffixed, not overwritten
  "$EDDA" new "Dup" >/dev/null; "$EDDA" rm dup --force >/dev/null
  "$EDDA" new "Dup" >/dev/null; "$EDDA" rm dup --force >/dev/null
  local n; n="$(find "$EDDA_VAULT/.trash" -name 'dup*.md' | wc -l | tr -d '[:space:]')"
  assert_eq "trash keeps both same-named deletes (no clobber)" "2" "$n"
}

# ── frontmatter vs. a body horizontal rule (the core gotcha) ─────────────────────
t_frontmatter_vs_hr(){
  fresh; "$EDDA" init >/dev/null; "$EDDA" new "Ruled" >/dev/null
  "$EDDA" add ruled "Above the rule." >/dev/null
  "$EDDA" add ruled -- "---" >/dev/null
  "$EDDA" add ruled "Below the rule." >/dev/null
  # fm_get must read ONLY the leading block — title stays correct despite the body ---
  assert_eq "fm_get not fooled by body ---" "Ruled" "$("$EDDA" read ruled --raw | sed -n 's/^title: //p')"
  # the body --- survives in the file
  assert_contains "body --- preserved" "$(cat "$EDDA_VAULT/ruled.md")" $'\n---\n'
  # the rendered body keeps the rule and both paragraphs
  local body; body="$("$EDDA" read ruled)"
  assert_contains "render keeps text above rule" "$body" "Above the rule."
  assert_contains "render keeps text below rule" "$body" "Below the rule."
}

# ── list + label filtering ───────────────────────────────────────────────────────
t_list(){
  fresh; "$EDDA" init >/dev/null
  "$EDDA" new "Alpha" >/dev/null
  "$EDDA" new -l work "Beta" >/dev/null
  local out; out="$("$EDDA" list)"
  assert_contains "list shows alpha" "$out" "alpha"
  assert_contains "list shows beta"  "$out" "beta"
  assert_contains "list shows count" "$out" "2 notes"
  out="$("$EDDA" list -l work)"
  assert_contains "list -l work shows beta"     "$out" "beta"
  assert_missing  "list -l work hides alpha"    "$out" "alpha"
  out="$("$EDDA" list work)"   # positional label shorthand
  assert_contains "list <label> shorthand" "$out" "beta"
}

# ── read: raw vs. rendered, and the render fallback ──────────────────────────────
t_read(){
  fresh; "$EDDA" init >/dev/null; "$EDDA" new "Readme Note" >/dev/null
  "$EDDA" add readme-note "visible body" >/dev/null
  assert_contains "--raw includes frontmatter"   "$("$EDDA" read readme-note --raw)" "title: Readme Note"
  assert_missing  "piped read strips frontmatter" "$("$EDDA" read readme-note)" "title: Readme Note"
  assert_contains "piped read shows body"         "$("$EDDA" read readme-note)" "visible body"

  # render fallback: hide glow/bat → read must still emit the body (degrade to plain)
  local mp; mp="$(shim_path "glow bat")"
  local out; out="$(PATH="$mp" "$EDDA" read readme-note)"
  assert_contains "read degrades without glow/bat" "$out" "visible body"

  # on a pty with glow/bat hidden, render_min runs and still surfaces the heading text.
  # 'script' is looked up on the normal PATH; the minimal PATH is handed only to edda.
  if command -v script >/dev/null 2>&1; then
    local pty
    pty="$(script -qec "PATH='$mp' EDDA_VAULT='$EDDA_VAULT' EDDA_CONFIG='$EDDA_CONFIG' '$EDDA' read readme-note --no-pager" /dev/null 2>/dev/null | tr -d '\r')"
    if [ -z "$pty" ]; then
      skip "render_min fallback on a TTY" "no usable pty here"
    else
      assert_contains "render_min fallback on a TTY" "$pty" "Readme Note"
    fi
  else
    skip "render_min fallback on a TTY" "no 'script'"
  fi
}

# ── search ───────────────────────────────────────────────────────────────────────
t_search(){
  fresh; "$EDDA" init >/dev/null; "$EDDA" new "Searchable" >/dev/null
  "$EDDA" add searchable "the needle is here" >/dev/null
  assert_contains "search finds a match" "$("$EDDA" search needle)" "needle"
  local out rc; out="$("$EDDA" search zzz-not-present)"; rc=$?
  assert_rc "search no-match returns 0" 0 "$rc"
  assert_contains "search no-match note" "$out" "no matches"
}

# ── search degrades to grep -r when rg is absent ─────────────────────────────────
t_search_grep_fallback(){
  fresh; "$EDDA" init >/dev/null; "$EDDA" new "Grepped" >/dev/null
  "$EDDA" add grepped "findable via grep" >/dev/null
  local d; d="$(shim_path "rg")"        # everyday tools, but no rg
  if PATH="$d" command -v rg >/dev/null 2>&1; then
    skip "search falls back to grep -r" "rg still visible"
    skip "grep fallback is case-insensitive" "rg still visible"
    skip "grep fallback supports regex alternation" "rg still visible"
  else
    assert_contains "search falls back to grep -r"                "$(PATH="$d" "$EDDA" search findable)" "findable"
    # parity with rg: the grep fallback matches case-insensitively (-i) …
    assert_contains "grep fallback is case-insensitive"           "$(PATH="$d" "$EDDA" search FINDABLE)" "findable"
    # … and understands extended regex, so '|' alternation works (-E)
    assert_contains "grep fallback supports regex alternation"    "$(PATH="$d" "$EDDA" search 'findable|absent')" "findable"
  fi
}

# ── path ─────────────────────────────────────────────────────────────────────────
t_path(){
  fresh; "$EDDA" init >/dev/null; "$EDDA" new "Pathy" >/dev/null
  assert_eq "path prints the note file" "$EDDA_VAULT/pathy.md" "$("$EDDA" path pathy)"
  local rc; "$EDDA" path nope >/dev/null 2>&1; rc=$?
  assert_rc "path of a missing note is rc 1" 1 "$rc"
}

# ── bareword fast-path ───────────────────────────────────────────────────────────
t_bareword(){
  fresh; "$EDDA" init >/dev/null; "$EDDA" new "Quick Look" >/dev/null
  "$EDDA" add quick-look "peek at me" >/dev/null
  assert_contains "bareword reads an existing note" "$("$EDDA" quick-look)" "peek at me"
  local out rc; out="$("$EDDA" definitely-not-a-note 2>&1)"; rc=$?
  assert_rc "bareword non-note is rc 1" 1 "$rc"
  assert_contains "bareword non-note errors cleanly" "$out" "no such command or note"
}

# ── pipe-safety: zero escapes when piped or under NO_COLOR ────────────────────────
t_pipe_safety(){
  fresh; "$EDDA" init >/dev/null; "$EDDA" new -l work "Clean Output" >/dev/null
  "$EDDA" add clean-output "some text" >/dev/null
  assert_no_esc "list piped: zero escapes"        "$("$EDDA" list)"
  assert_no_esc "list -l piped: zero escapes"     "$("$EDDA" list -l work)"
  assert_no_esc "read piped: zero escapes"        "$("$EDDA" read clean-output)"
  assert_no_esc "search piped: zero escapes"      "$("$EDDA" search text)"
  assert_no_esc "path piped: zero escapes"        "$("$EDDA" path clean-output)"
  assert_no_esc "NO_COLOR list: zero escapes"     "$(NO_COLOR=1 "$EDDA" list)"
  assert_no_esc "help piped: zero escapes"        "$("$EDDA" help)"
}

# ── config/vault resolution ladder: env > file > default ─────────────────────────
t_ladder(){
  local envv filev conf; envv="$(mkd)"; filev="$(mkd)"; conf="$(mkd)/config"
  printf 'EDDA_VAULT="%s"\n' "$filev" > "$conf"

  # env beats the config file
  EDDA_VAULT="$envv" EDDA_CONFIG="$conf" "$EDDA" new "Ladder" >/dev/null
  assert_file "env vault wins over config file" "$envv/ladder.md"
  assert_missing "config-file vault untouched when env set" "$(ls "$filev")" "ladder.md"

  # file beats the default when env is unset
  local out
  out="$(env -u EDDA_VAULT EDDA_CONFIG="$conf" "$EDDA" new "FromFile" 2>&1)"
  assert_file "config-file vault used when env unset" "$filev/fromfile.md"

  # default when neither env nor a config file is present
  local dh; dh="$(mkd)"
  out="$(env -u EDDA_VAULT EDDA_CONFIG="$conf.nope" XDG_DATA_HOME="$dh" "$EDDA" help)"
  assert_contains "default vault = XDG_DATA_HOME/edda" "$out" "$dh/edda"
}

# ── labels: overview counts, show, add/remove, no-ops, empty-label guard ─────────
t_labels(){
  fresh; "$EDDA" init >/dev/null
  "$EDDA" new -l work -l urgent "Retro Prep" >/dev/null
  "$EDDA" new -l work "Standup" >/dev/null
  "$EDDA" new "Loose" >/dev/null

  # overview: every label in use, with counts
  local ov; ov="$("$EDDA" labels)"
  assert_contains "labels overview lists a label"       "$ov" "work"
  assert_contains "labels overview counts uses (2)"     "$ov" "2 note"
  assert_contains "labels overview totals label count"  "$ov" "2 labels"

  # show one note's labels
  assert_contains "labels <note> shows its labels" "$("$EDDA" labels retro-prep)" "urgent"

  # -a/-r rewrite the frontmatter labels: field in place
  "$EDDA" labels retro-prep -a idea -r urgent >/dev/null
  local lf; lf="$("$EDDA" read retro-prep --raw | sed -n 's/^labels: //p')"
  assert_contains "labels -a adds a label"    "$lf" "idea"
  assert_missing  "labels -r removes a label" "$lf" "urgent"

  # adding a duplicate / removing an absent label are no-ops
  "$EDDA" labels standup -a work >/dev/null
  assert_eq "labels -a duplicate is a no-op" "[work]" "$("$EDDA" read standup --raw | sed -n 's/^labels: //p')"
  "$EDDA" labels standup -r ghost >/dev/null
  assert_eq "labels -r absent is a no-op"    "[work]" "$("$EDDA" read standup --raw | sed -n 's/^labels: //p')"

  # a note with no labels
  assert_contains "labels <note> with none says so" "$("$EDDA" labels loose)" "no labels"

  # new -l with an unsluggable value must not wedge an empty entry into the list
  "$EDDA" new -l '!!!' "Junk Label" >/dev/null
  assert_eq "new drops an unsluggable label" "[]" "$("$EDDA" read junk-label --raw | sed -n 's/^labels: //p')"

  assert_no_esc "labels overview piped: zero escapes" "$("$EDDA" labels)"
}

# ── mv/rename: re-slug + retitle in sync, same-slug retitle, collision refuse ────
t_mv(){
  fresh; "$EDDA" init >/dev/null
  "$EDDA" new -l work "Reading List" >/dev/null
  "$EDDA" add reading-list "GEB" >/dev/null
  local created; created="$("$EDDA" read reading-list --raw | sed -n 's/^created: //p')"

  # a real rename: the file moves, the title syncs, created + body are preserved
  "$EDDA" mv reading-list "Books to read" >/dev/null
  if [ -f "$EDDA_VAULT/reading-list.md" ]; then fail "mv moves the file off the old slug"
  else pass "mv moves the file off the old slug"; fi
  assert_file "mv creates the new slug"     "$EDDA_VAULT/books-to-read.md"
  assert_eq "mv syncs the title"            "Books to read" "$("$EDDA" read books-to-read --raw | sed -n 's/^title: //p')"
  assert_eq "mv preserves created"          "$created" "$("$EDDA" read books-to-read --raw | sed -n 's/^created: //p')"
  assert_contains "mv preserves the body"   "$("$EDDA" read books-to-read --raw)" "GEB"

  # same slug → a title-only change; the file stays put
  "$EDDA" mv books-to-read "Books To READ" >/dev/null
  assert_file "same-slug mv keeps the file"       "$EDDA_VAULT/books-to-read.md"
  assert_eq "same-slug mv updates the title"      "Books To READ" "$("$EDDA" read books-to-read --raw | sed -n 's/^title: //p')"

  # never overwrite a different existing note
  "$EDDA" new "Target" >/dev/null
  local rc; "$EDDA" mv books-to-read "Target" >/dev/null 2>&1; rc=$?
  assert_rc "mv onto an existing note refuses" 1 "$rc"
  if [ -f "$EDDA_VAULT/books-to-read.md" ] && [ -f "$EDDA_VAULT/target.md" ]; then pass "mv collision leaves both notes intact"
  else fail "mv collision leaves both notes intact"; fi

  # missing source, and an unsluggable new name
  "$EDDA" mv ghost "X"  >/dev/null 2>&1; rc=$?; assert_rc "mv of a missing note is rc 1"       1 "$rc"
  "$EDDA" mv target "!!!" >/dev/null 2>&1; rc=$?; assert_rc "mv to an unsluggable name is rc 1" 1 "$rc"
}

# ── run everything ───────────────────────────────────────────────────────────────
printf '\nedda test harness — %s\n\n' "$EDDA"
[ -x "$EDDA" ] || { printf 'edda not executable at %s\n' "$EDDA" >&2; exit 2; }

t_init
t_new_frontmatter
t_new_labels
t_slug_edges
t_add
t_edit
t_rm
t_mv
t_frontmatter_vs_hr
t_list
t_labels
t_read
t_search
t_search_grep_fallback
t_path
t_bareword
t_pipe_safety
t_ladder

printf '\n  %d passed, %d failed\n\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
