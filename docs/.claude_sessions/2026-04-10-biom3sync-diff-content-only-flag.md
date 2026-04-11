# 2026-04-10 — biom3sync diff `--content-only` flag

Short follow-up session to the morning's biom3sync work (set-e fix +
manifest normalization). Motivated directly by the output the user got
from `biom3sync diff spark` after the manifest commit landed.

## Original prompts

User turns in the session:

> when I run biom3sync diff spark on my local repo, I see: *(pasted a
> ~200-line rsync itemize-changes dump — dozens of `.d...p...`,
> `.f...p...`, `.d..t....`, a few `.d...p.g.`, and some real
> `<f+++++++` / `>f+++++++` lines mixed in)*

*(Task was first to interpret the output, then act on the finding.)*

> yes *(agreeing to add a `--content-only` mode to cut metadata noise out
> of `diff`)*

> Write a session note and commit

## Context

After landing manifest normalization, the user ran `biom3sync diff spark`
on their local host and got a wall of rsync itemize-changes lines. The
volume made it hard to see the real drift. Decoding the flag columns
(`YXcstpogu…` — position 6 = perms, 8 = group, 5 = mtime) showed that
only ~5% of the lines were real content differences:

**Real content drift:**
- `manifest.json` / `manifest.txt` had been regenerated locally in the
  previous session, so spark's copies were older (self-inflicted; would
  resolve on next push).
- Dataset file naming difference between hosts:
  - **Local only**: `datasets/Pfam-A.full.gz`,
    `datasets/Pfam_protein_text_dataset.csv`,
    `datasets/fully_annotated_swiss_prot.csv`
  - **Spark only**: `datasets/LEGACY_Pfam_protein_text_dataset.csv`,
    `datasets/LEGACY_fully_annotated_swiss_prot.csv`,
    `datasets/README.md`

  Looks like the two large CSVs were renamed on spark to mark them
  legacy, plus a README.md was added; local hasn't caught up and also
  still has a `Pfam-A.full.gz` that spark is missing. Open question:
  are the `LEGACY_*` files byte-identical to the unprefixed ones, or
  are they actually different content?

**Noise:**
- Dozens of `.d...p...` / `.f...p...` lines where *only* permissions
  differed — residue of the permissions lockdown work not being applied
  symmetrically across hosts.
- `.d...p.g.` on `test_dir/` and `.f.....g.` on its files — group bit
  drifted too.
- `.d..t....` on `./` and `datasets/` — directory mtime nudged by
  something.

The user's read after the interpretation: they wanted a way to make
`diff` useful for content-drift detection without deliberately hunting
through metadata noise. Decision: add a `--content-only` mode. Default
behavior stays unchanged (someone might legitimately want to see
permission drift — the morning's lockdown work is exactly that kind of
situation).

## Changes

All in [sync/biom3sync.sh](../../sync/biom3sync.sh), `cmd_diff` and the
top-of-file usage header.

**New arg parser in `cmd_diff`.** A small option loop before the
positional args accepts `--content-only`, handles `--` as an explicit
end-of-options, errors on unknown flags, and breaks on the first
positional. Kept local to `cmd_diff` rather than hoisting to the global
parser — the flag is only meaningful for `diff`, same pattern as
`cmd_manifest`'s `-d` / `--no-checksum`.

**Rsync flags.** When `--content-only` is set, `cmd_diff` appends
`--no-perms --no-group --no-owner --omit-dir-times` to the existing
`-azn --itemize-changes` base. File mtimes are still compared, so real
content changes (anything detected by rsync's size+mtime quick-check)
still show up — only metadata-only noise gets filtered.

**Header tag.** The `Comparing local ↔ ${remote}  ${subpath}/` header
gets a `  [content-only]` suffix in content-only mode, so it's obvious
from the output alone which mode ran.

**Usage header + example.** The top-of-file USAGE block's `diff` line
documents the new flag; a new example line shows the typical invocation.

One nit caught during implementation: first pass used
`${content_only:+  [content-only]}` for the header tag, which always
expanded because `"false"` is a non-empty string. Replaced with an
explicit `if $content_only; then header+=…; fi`.

## Verification

Against polaris on the real data tree:

- Default mode: **220 lines** of itemize output (the noisy baseline).
- `--content-only` mode: **18 lines**, and the 18 surviving lines are
  exactly:
  - `manifest.json` / `manifest.txt` on both sides (self-inflicted
    re-generation drift — will clear on next push).
  - Entire `nm-team-data/` subtree as new on local (the known content
    delta from the morning's session).

All metadata-only noise (`.d...p...`, `.d..t....`, `.d...p.g.`,
`.f.....g.`) is gone.

Arg-parser edge cases:

- `diff --content-only` (no REMOTE) → prints the updated usage line,
  exits 1. ✓
- `diff --bogus polaris` → `Unknown diff option: --bogus`, exits 1. ✓
- `diff --content-only polaris datasets/CM` → subpath still honored,
  header reads `Comparing local ↔ polaris  datasets/CM/  [content-only]`,
  shows `(in sync)` (which is also correct — that subtree matches
  between hosts). ✓

`bash -n` clean.

## Deferred / not addressed

- **The actual Pfam/swissprot drift.** The `--content-only` flag made it
  clearly visible but did not resolve it. Still an open question whether
  the `LEGACY_*` files on spark are the same bytes as the unprefixed
  files on local or genuinely different content. Next time someone is
  working in that dataset area, they should decide whether to rename
  locally to match spark or vice versa, and whether to copy over
  `README.md` / `Pfam-A.full.gz` in whichever direction is correct.
- **Permission drift across hosts.** The morning's lockdown work applied
  setgid + strict perms on one host; other hosts are still carrying
  looser perms. Not a bug in `biom3sync`; the reason `--content-only`
  exists is specifically so this kind of expected-but-noisy drift
  doesn't bury real content deltas. A follow-up pass of the lockdown
  runbook on the other hosts would eliminate the noise at the source.

## State at end of session

- Branch `addison-dev`.
- Commits added this session (on top of the morning's work):
  - `feat(biom3sync): add diff --content-only flag to skip metadata drift`
    *(pending — this session note is being committed alongside it)*
- `docs/.claude_prompts/` still untracked.
- Not pushed.
