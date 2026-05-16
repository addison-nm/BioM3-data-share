# Add UniRef100/90/50 to download pipeline

**Date:** 2026-05-16
**Branch:** dev
**Pre-session commit:** `b500f63` (chore(version): bump to 0.1.0a2)

## Summary

Added UniRef100, UniRef90, and UniRef50 (UniProt Reference Clusters) as three
**independent**, separately selectable databases in the download pipeline.
Each lands in its own folder (`databases/uniref100/`, `.../uniref90/`,
`.../uniref50/`) and downloads exactly three files: the clustered FASTA, the
per-dataset release note, and the generic UniRef README. Implementation follows
the existing `download_trembl()` pattern. No combined `uniref` alias was added
(deliberate — see Decisions).

## Files changed

- `download/download_databases.sh`
  - `ALL_DBS` — added `uniref100 uniref90 uniref50` after `trembl`.
  - New `download_uniref_tier <NN>` helper + thin `download_uniref100/90/50`
    wrappers, inserted as section "4b" after `download_trembl()`.
  - Three dispatcher `case` arms after `trembl)`.
  - Help-text comment block extended; `usage()` print range bumped
    `sed -n '3,20p'` → `'3,22p'` (the wrapped valid-list pushed the `-h` line
    past 20 — without this the help output would silently truncate).
- `download/README.md` — overview table rows, disk-space estimate
  (580 → 780 GB), new `### 4b. UniRef` section (URL base, file table,
  README-naming note, integrity note, citation, reproducibility note), output
  structure tree blocks, reproducibility checklist entry, and the
  "eight → eleven databases" prose count.

(`CLAUDE.md` was **not** touched — its `download/` description is a high-level
list and was left as-is; the trembl precedent edited it, but the project root
CLAUDE.md no longer enumerates individual DBs in a way that needs updating.)

## Details

- **Source:** `https://ftp.uniprot.org/pub/databases/uniprot/uniref/uniref<NN>/`
  (`<NN>` ∈ {100, 90, 50}). Note this is the `uniref/` tree, **not** the
  `current_release/knowledgebase/complete/` path used by SwissProt/TrEMBL.
- **Files downloaded per tier:**
  - `uniref<NN>.fasta.gz` — clustered representative sequences
    (uniref100 ≈ 120 GB, uniref90 ≈ 47 GB, uniref50 ≈ 13 GB compressed;
    sizes from live `Content-Length` HEADs)
  - `uniref<NN>.release_note` — ~311 B per-dataset release metadata
  - `uniref<NN>.README` — the upstream `README` (verbatim content), saved
    under a **dataset-qualified local name**
- **Not downloaded:** `uniref<NN>.xml.gz`, `RELEASE.metalink`, `uniref.xsd`.
- **Usage:** `bash download_databases.sh -d uniref50 -o ./databases`

### Key decisions

1. **Three independent IDs, no `uniref` alias** (user-confirmed). Given the
   sizes (uniref100 ≈ 120 GB), granular `-d` selection is essential and matches
   the per-DB convention; a combined alias would force 180 GB+ even when only
   one tier is wanted.
2. **README saved as `uniref<NN>.README`, not literal `README`.** All three
   upstream READMEs share the basename `README`. Both
   `_record_provenance_if_new()` (dedups by `basename`) and
   `verify_checksums.sh` (`find -name`) key on basename only — a literal
   `README` would collapse all three provenance rows into one and make
   verification resolve ambiguously across folders. Dataset-qualifying the
   local name makes every basename unique and parallels the existing
   `uniref<NN>.fasta.gz` / `.release_note` naming. On-disk content is the
   upstream README verbatim.
3. **No `expected_md5`.** UniProt publishes no `.md5` sidecars for UniRef
   (checksums live only inside `RELEASE.metalink` XML). Parsing metalink would
   add an XML dependency used nowhere else; instead we rely on the existing
   size-based idempotency gate — identical to how TrEMBL/SwissProt/Pfam work.
   The computed post-download MD5 is still recorded in `provenance.tsv`.

## Verification performed

- `bash -n` — clean. (`shellcheck` not installed; skipped.)
- `-h` help output shows the new IDs **and** the final `-h` line intact
  (confirms the `sed` range fix).
- All 9 remote URLs (3 tiers × {fasta.gz, release_note, README}) return
  HTTP 200 — URL construction correct for every tier.
- Functional run of `-d uniref50` against a `/tmp` scratch dir, with a
  size-matched **sparse placeholder** pre-staged for the 12.7 GB
  `uniref50.fasta.gz` so the size gate skipped it and the real
  dispatcher → `download_file` → provenance path ran on the two small files:
  - `uniref50.release_note` (311 B) and `uniref50.README` (6953 B, genuine
    "Universal Protein Resource (UniProt)" content) downloaded.
  - `provenance.tsv`: three **unique** basenames — never a bare `README`.
  - Idempotent re-run: all three skipped, **zero** duplicate provenance rows.
  - `verify_checksums.sh`: **PASS=3 FAIL=0 SKIP=0**, `uniref50.README`
    resolved 1:1.
- Scratch dir removed; the only repo-tracked changes are the two `download/`
  files. (The run appended to the gitignored `.logs/download_20260516.log`,
  the script's normal log location — not a tracked change.)

## Lingering / not done

- **Full real FASTA download not exercised.** The functional test deliberately
  skipped the multi-GB FASTA via a size-matched placeholder. The real transfer
  path (`curl -C -` resume on a 13–120 GB file) is unchanged from TrEMBL and
  relied upon there, so it is considered covered by precedent. An optional
  end-to-end `-d uniref50` to completion (~13 GB) was offered but not run.
- **`shellcheck` not available** on this machine, so only `bash -n` static
  validation was done.
- No automated test suite exists for the download scripts (pre-existing); none
  was added — consistent with the rest of the pipeline.

## Restore pre-session state

Working tree was clean at session start. To return to the pre-session state:

```bash
git checkout b500f63 -- download/download_databases.sh download/README.md
# or, to move the whole tree back:
git checkout b500f63
```

## Commit

This note and the two `download/` changes are committed together immediately
after this note is written (see the session's commit on the `dev` branch).
