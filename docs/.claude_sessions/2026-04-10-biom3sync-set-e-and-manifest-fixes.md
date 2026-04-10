# 2026-04-10 — biom3sync set -e bug fix + manifest cross-host normalization

Two independent fixes to `sync/biom3sync.sh`, landed as separate commits on
`addison-dev`:

1. `2ec10f2` — fix: stop `set -e` from silently killing push/pull/diff when
   run without `-v`.
2. `1fcdc2b` — refactor: normalize manifest output so macOS and Linux hosts
   produce byte-identical `manifest.txt` / `manifest.json` against the same
   tree.

Both were driven by prompt plans drafted earlier in `docs/.claude_prompts/`
and executed back-to-back in this session.

## Original prompts

User turns in the session:

> I need to implement the bug fix described in this file. *(IDE-opened
> `docs/.claude_prompts/fix_announce_excludes_bug_in_biom3sync.md`)*

> I'll do normalization next. Commit this

> The next fix is described in this file *(IDE-opened
> `docs/.claude_prompts/improve_checksums.md`)*

> let's commit

> Write a session note, including the original prompts

### Prompt 1 — `fix_announce_excludes_bug_in_biom3sync.md`

````markdown
# Implementation plan: fix `announce_excludes` `set -e` bug in `biom3sync.sh`

Target repo: BioM3-data-share
Target file: `sync/biom3sync.sh`
Target branch: development branch (to ride along with the manifest cross-host normalization work)
Date drafted: 2026-04-10

## Summary

Fix a `set -e` / bash-conditional bug in `sync/biom3sync.sh` that causes `push`, `pull`, and `diff` commands to silently exit partway through whenever they are run without `-v`. The script returns to the shell with no rsync output, no `Done. (Xs)` line, and no error message. Adding `-v` "fixes" it by accident. The real fix is a small rewrite of one function.

## Symptom

Running any of these without `-v` prints only the header lines and then returns to the prompt:

```
$ biom3sync push spark
→ push  spark  ./
$
```

```
$ biom3sync -n pull spark
← pull  spark  ./
  [dry run — no files will be transferred]
$
```

```
$ biom3sync diff polaris
Comparing local ↔ polaris  ./
$
```

No rsync is invoked. No error is printed. The same commands with `-v` added run to completion normally.

## Root cause

`announce_excludes` at `sync/biom3sync.sh:168-174`:

```bash
announce_excludes() {
    if [[ -f "$EXCLUDES_FILE" ]]; then
        $VERBOSE && echo "  using excludes: $EXCLUDES_FILE"
    elif [[ -f "$EXCLUDES_EXAMPLE" ]]; then
        echo "  hint: cp config/excludes.example config/excludes  to enable custom excludes"
    fi
}
```

When `VERBOSE=false` and the excludes file exists, the body expands to `false && echo …`:

1. `false` returns exit code 1.
2. `&&` short-circuits; the compound command's exit status is 1.
3. That is the last statement in the function body, so the function returns 1.
4. The script has `set -euo pipefail` at the top.
5. `announce_excludes` is called as a bare statement (not in a conditional, not followed by `||`) from both `do_sync` and `cmd_diff`.
6. `set -e` treats the non-zero return as a fatal error and terminates the whole script silently.

With `-v`, `VERBOSE=true`, so `true && echo …` returns 0 and the script proceeds normally. `-v` is masking the bug, not fixing it.

## Fix

Rewrite `announce_excludes` to avoid the `<cmd> && <cmd>` tail pattern and add an explicit `return 0`:

```bash
announce_excludes() {
    if [[ -f "$EXCLUDES_FILE" ]]; then
        if $VERBOSE; then
            echo "  using excludes: $EXCLUDES_FILE"
        fi
    elif [[ -f "$EXCLUDES_EXAMPLE" ]]; then
        echo "  hint: cp config/excludes.example config/excludes  to enable custom excludes"
    fi
    # Explicit return 0 so set -e doesn't kill the script if the last echo is skipped.
    return 0
}
```

Both changes are load-bearing:

- The `if $VERBOSE; then … fi` restructure handles the immediate bug — the `if` block's exit status is 0 regardless of whether the `echo` ran.
- The explicit `return 0` is defense-in-depth. If someone later adds a conditional branch whose last command can legitimately return non-zero, the function still will not accidentally torpedo the script.
- The comment above `return 0` is important. Without it, a future reader will almost certainly "clean up" the line as unreachable or redundant.

## Audit pass

Check for the same pattern elsewhere in the script. Search for `$VARNAME && <cmd>` and similar `bool && cmd` constructs:

```bash
grep -n '\$[A-Z_][A-Z_]* &&' sync/biom3sync.sh
```

Any that appear **as the last statement of a function** or **as a bare statement at script level** under `set -e` are latent versions of this bug. Fix them the same way — restructure to `if $FLAG; then …; fi` and add `return 0` if needed.

Known call sites that are already safe (do not touch, but verify during audit):

- `rsync_base_flags` uses `$DRY_RUN && flags+=(--dry-run)` and `$VERBOSE && flags+=(-v)` — safe because they are followed by `echo "${flags[@]}"`, so the tail exit status is the echo's, not the conditional's.
- `do_sync` uses `$DRY_RUN && echo "  [dry run — no files will be transferred]"` — this one is at risk. In practice it appears to work because the next statement is `announce_excludes`, which before the fix crashes the script anyway so the bug is masked. After fixing `announce_excludes`, verify `$DRY_RUN && echo …` does not become the new silent-exit point. If `DRY_RUN=false`, the command returns 1 and `set -e` will kill the script. **This is a second instance of the same bug and must also be fixed.** Rewrite to:

  ```bash
  if $DRY_RUN; then
      echo "  [dry run — no files will be transferred]"
  fi
  ```

- Any other instances the grep turns up — fix them with the same pattern.

## Acceptance test

After the fix, all of these should run to completion and print their normal output with no `-v`:

```bash
biom3sync -n push spark
biom3sync -n pull spark
biom3sync diff polaris
biom3sync -n push aurora datasets/CM
```

Each should exit with status 0:

```bash
biom3sync -n push spark; echo "exit: $?"
```

Before the fix, these exit with a non-zero status (whatever `announce_excludes` returned) and the tail of the expected output is missing.

Also verify that `-v` still works the same as before — the fix should be invisible to verbose mode.

## Why this matters

The user hit this bug while debugging a separate issue (comparing manifests between hosts) and it burned significant time because the failure mode is so quiet: no error message, no stderr, just a script that stops halfway. The initial debugging session mis-attributed the symptom to rsync being quiet in non-verbose mode, which sent the investigation in the wrong direction for several iterations. Silent script exits under `set -e` are a well-known bash footgun and the script should be robust against them.

A defensive alternative is adding `|| true` at the call sites of `announce_excludes`:

```bash
announce_excludes || true
```

This would mask the immediate symptom but is strictly worse than fixing the function itself — it would also mask future bugs inside `announce_excludes`'s actual logic. The function-internal fix is the right answer. `|| true` is not a substitute.

## What not to touch

- The body of `do_sync`, `cmd_diff`, `cmd_push`, `cmd_pull` — the fix is inside `announce_excludes` plus any additional instances the audit turns up (likely just the `$DRY_RUN && echo` line in `do_sync`).
- The `set -euo pipefail` line at the top of the script. Strict mode is correct; the fix is to write bash that respects it.
- The output format of the `using excludes:` and `hint:` lines. Only the control flow around them changes.
- The behavior with `-v` set. Verbose mode should work identically before and after the fix.

## Delivery

- Patch to `sync/biom3sync.sh` only.
- Small diff — approximately 5-10 lines for the `announce_excludes` rewrite plus 3 lines for the `$DRY_RUN && echo` fix in `do_sync`, plus any further audit fixes.
- Include the `# Explicit return 0 …` comment above the `return 0`. The reason is non-obvious and a future reader might strip it out otherwise.
- Order in the PR: this fix should land as its own commit, separate from the manifest normalization commit, so the two concerns are reviewable independently. Normalization is the larger and more invasive change; it makes sense to land normalization first and this fix second, so the fix applies cleanly on top.
````

Deviation from the plan's "order in the PR" guidance: the set-e fix landed
*first* (2ec10f2), manifest normalization *second* (1fcdc2b). The ordering
swap was deliberate — with the set-e bug still in place, smoke-testing the
normalization commit on the real tree would have been impossible (the
script would silently exit before reaching the rsync path during any
verification check).

### Prompt 2 — `improve_checksums.md`

````markdown
Normalize cmd_manifest in sync/biom3sync.sh so that data/manifest.txt and data/manifest.json are byte-identical across macOS (BSD coreutils) and Linux (GNU coreutils) hosts when the underlying file tree is identical. Today, running biom3sync manifest on a Mac and on a Linux box against the same content produces manifests that diff in ~80% of lines purely due to OS dialect, which defeats the purpose of using manifests to compare hosts.

Three drift sources need to be eliminated:

Size formatting via du -sh — BSD floors human-readable sizes (e.g. 34G) while GNU rounds up (e.g. 35G). Every non-trivial size line drifts. Also, BSD prints 0B for empty files and GNU prints 0. And sub-MB directory sizes can drift further because BSD/GNU use different default block sizes.

Fix: stop shelling out to du -sh in _manifest_walk. For files, use the existing file_size_bytes helper (already byte-accurate and cross-platform). For directories, recursively sum bytes from the walker itself — you're already visiting every entry, so accumulate a per-directory byte total as you unwind. Then add a single Bash pretty-printer (e.g. format_size_human) that takes a byte count and emits a deterministic string like 34G, 1.2M, 4.0K, 0. Pick one rounding rule (suggest: round-half-up to one decimal below 10, whole number at/above 10, e.g. 1.2M but 34G) and document it in a comment. Emit 0 (not 0B) for empty.

Locale-dependent sort order — find … | sort in _manifest_walk uses whatever LC_COLLATE the host has. macOS default collates ASCII bytes so .gitkeep sorts before datasets/; Linux default treats leading dots as insignificant so .gitkeep sorts as gitkeep and lands between datasets/ and manifest.json. Same issue inside subdirectories (_README.md moves around).

Fix: force LC_ALL=C for the find | sort invocation (and anywhere else sort order matters) so it's deterministic byte ordering on every host. A one-line change: LC_ALL=C find "$dir" -maxdepth 1 -mindepth 1 | LC_ALL=C sort.

Tree-drawing prefix — already deterministic, leave alone.

Acceptance test: On macOS and Linux, against an identical data/ tree, biom3sync manifest should produce data/manifest.txt files with matching md5s. A minimal reproducible test: create a small fixture tree with a mix of empty files, sub-KB files, multi-MB files, a dotfile, and a subdirectory with _prefixed entries; generate the manifest on two hosts (or simulate by running under LC_ALL=C vs LC_ALL=en_US.UTF-8 and by swapping du/coreutils); diff should be empty.

Don't touch:

The manifest.json schema — size_bytes there is already exact.
The md5 column — already deterministic.
The --no-checksum path — still valid.
The timestamp in the header — that's supposed to differ.
Gotcha: file_size_bytes uses stat -f%z on Darwin and stat -c%s on Linux; keep using it for files. For symlinks, decide whether to report link size or target size — match current behavior (which follows links via du) unless you find a bug.

Context for why this matters: users diff manifests between machines to find real content drift (missing files, stale copies, etc.). When 80% of diff lines are cosmetic, the real signal is lost. We caught a genuine content delta (nm-team-data/ on spark only) that was nearly buried in rounding noise.

Deliver: patch to sync/biom3sync.sh only. No new files. Keep the diff tight — don't refactor _manifest_walk more than needed.
````

## Fix 1 — `announce_excludes` set -e bug (`2ec10f2`)

### Context

`sync/biom3sync.sh` runs under `set -euo pipefail`. The function
`announce_excludes` ended with `$VERBOSE && echo …` as its last statement
inside the `if [[ -f "$EXCLUDES_FILE" ]]` branch. When `VERBOSE=false` and
the excludes file existed, the `false && echo …` tail made the function
return 1 — which, because `announce_excludes` was called as a bare
statement from `do_sync` and `cmd_diff`, tripped `set -e` and silently
killed the whole script. Symptom: push/pull/diff printed only the header
line, then returned to the shell with no rsync output, no error, and no
"Done." line. Adding `-v` "fixed" it by accident because `true && echo …`
returns 0.

The user had hit this bug while debugging manifest comparisons between
hosts and burned real time on it — initial investigation mis-attributed
the symptom to rsync being quiet in non-verbose mode.

### Changes

Two restructures in [sync/biom3sync.sh](../../sync/biom3sync.sh):

1. **`announce_excludes`** — `$VERBOSE && echo …` → `if $VERBOSE; then …; fi`,
   with an explicit `return 0` at the end of the function and a comment
   explaining why the `return 0` is load-bearing (so a future reader
   doesn't delete it as redundant).
2. **`do_sync`** — the `$DRY_RUN && echo "  [dry run …]"` line, same
   treatment. The prompt called this out as a latent second instance of
   the same pattern that would become exposed after fixing
   `announce_excludes`.

Audit grep for `$[A-Z_]+ &&` across the script turned up six total matches.
The other four (lines 151, 152 in `rsync_base_flags`, 416 in `cmd_diff`,
529 in `_manifest_walk`) are all followed by another statement so their
exit status doesn't become the enclosing function's — left alone.

### Verification

- `bash -n` clean.
- `biom3sync -n push polaris` (no `-v`) — previously exited silently after
  the header; now runs rsync to completion and prints `Done. (1s)`.
- Exercised the exact buggy branch by copying `config/excludes.example` to
  `config/excludes` and re-running without `-v`: runs through to `Done.`
- `biom3sync -v -n push polaris` (verbose mode) — identical behavior to
  before the fix, as required by the plan.

## Fix 2 — Manifest cross-host normalization (`1fcdc2b`)

### Context

`biom3sync manifest` generated `data/manifest.{txt,json}` whose output
drifted substantially between macOS (BSD coreutils) and Linux (GNU
coreutils) hosts against identical file trees. Three drift sources:

1. **`du -sh` dialect** — BSD floors human-readable sizes (34G), GNU rounds
   up (35G); BSD prints `0B` for empty files, GNU prints `0`; sub-MB
   directory sizes differ further due to default block-size differences.
2. **Locale-dependent `sort`** — default `LC_COLLATE` on macOS sorts
   dotfiles first (`.gitkeep` before `datasets/`); default on Linux
   glibc often treats leading dots as insignificant, moving `.gitkeep`
   between `datasets/` and `manifest.json`. Same thing happens to
   `_README.md` inside subdirs.
3. Tree-drawing prefix — already deterministic, left alone.

Cosmetic diff was so dominant (~80% of lines) that real content drift was
getting buried. The immediate motivator: a genuine content delta
(`nm-team-data/` present only on spark) was nearly missed in the rounding
noise.

### Changes

All in [sync/biom3sync.sh](../../sync/biom3sync.sh), `_manifest_walk` and
a new helper above it.

**New helper `format_size_human`.** Pure-integer bash formatter. Picks the
smallest unit whose raw value is < 1024. Within a unit, values < 10 print
as `X.Y` (one decimal, round-half-up); values ≥ 10 print as an integer
(round-half-up). Empty files print as `0` (no unit). Round-half-up is
implemented as `(bytes * 10 + scale / 2) / scale` so everything stays
integer and deterministic — no locale-sensitive `printf` rounding.

**`_manifest_walk` rewrite.**

- Deterministic ordering: `LC_ALL=C find … | LC_ALL=C sort`.
- Files: use `file_size_bytes` (already BSD/GNU-safe) then
  `format_size_human`. No more `du -sh` per file.
- Directories: byte totals now accumulate during the walk itself via a new
  scalar global `_SUBTREE_BYTES`. Each `_manifest_walk` call writes its
  own subtree total to `_SUBTREE_BYTES` right before returning; the
  caller reads it into a local immediately after the recursive call,
  before any other recursion can overwrite it.
- Depth gating: the walker now always traverses the full tree (so parent
  dirs still get accurate totals when the display depth is exhausted),
  but an `emit` flag gates whether entries are appended at the current
  level. `[[ $depth -le 0 ]] && emit=false` replaces the old early
  `return`.
- Parent-before-children ordering: the dir line can't be emitted until
  after its recursive call completes (that's when the subtree total is
  known). Solution: reserve a placeholder slot in `_TXT_LINES` /
  `_JSON_ENTRIES` before recursing, remember the indices as
  `dir_txt_idx` / `dir_json_idx`, then backfill those slots once the
  recursive call returns.

Preserved unchanged, as the prompt specified:
- `manifest.json` schema (no new `size_bytes` field on dir entries).
- `md5` column and `--no-checksum` path.
- Header timestamp (expected to differ between runs).
- `file_size_bytes` behavior for symlinks (no active bug found).

### Verification

`format_size_human` unit test across tier boundaries:

```
               0  ->  0
               1  ->  1
             512  ->  512
            1023  ->  1023
            1024  ->  1.0K
            1536  ->  1.5K
           10188  ->  9.9K
           10240  ->  10K
           10752  ->  11K     (exactly 10.5K, round-half-up)
         1048575  ->  1024K
         1048576  ->  1.0M
     34359738368  ->  32G
     36507222016  ->  34G
```

Cross-locale determinism test with a fixture tree at
`/tmp/biom3_manifest_fixture` containing a dotfile (`.gitkeep`), an empty
file, an underscored sibling (`_README.md`), nested subdirs, and a
multi-MB random-data file:

```
data/  (generated …, depth=4, checksums=false)
├── .gitkeep  [3]
├── datasets/  [1.5M]
│   ├── CM/  [1.5M]
│   │   └── big.bin  [1.5M]
│   ├── SH3/  [6]
│   │   └── tiny.txt  [6]
│   └── _README.md  [7]
├── empty_file.txt  [0]
├── weights/  [8]
│   └── PenCL/  [8]
│       └── model.pt  [8]
└── zfinal.txt  [7]
```

Run 1: `LC_ALL=C biom3sync manifest --no-checksum -d 4`
Run 2: `LC_ALL=en_US.UTF-8 biom3sync manifest --no-checksum -d 4`

`diff` of both `manifest.txt` and `manifest.json` (ignoring the timestamp
header line): **MATCH**. Dotfile sorts first in both runs, `_README.md`
sorts after uppercase in both runs, empty files show `[0]` in both.

End-to-end on the real data tree at `/data/data-share/BioM3-data-share`:
- Back-to-back runs produce byte-identical output (modulo timestamp).
- `datasets/` totals to 133G, `weights/` to 13G.
- `datasets/CM/` sorts as
  `FINAL_CM_all_dataset_with_prompts.csv` → `_README.md` → `aba3304_*`,
  which is exact C-locale byte order (`F` 0x46 < `_` 0x5F < `a` 0x61).

## State at end of session

- Branch `addison-dev`, 2 commits ahead of `origin/dev`:
  - `1fcdc2b refactor(biom3sync): normalize manifest output across BSD/GNU hosts`
  - `2ec10f2 fix(biom3sync): stop set -e from killing script on non-verbose runs`
- `docs/.claude_prompts/` still untracked (prompt plan files, not
  committed).
- No working tree changes.
- Not pushed.
