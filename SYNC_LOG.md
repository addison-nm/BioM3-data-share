# BioM3-dev Sync Log

Tracks which versions of BioM3-dev produced the weights, datasets, and database
configurations stored in this repository.

| Date | BioM3-dev commit | BioM3-dev version | data-share commit | Summary |
| ---- | ---------------- | ----------------- | ----------------- | ------- |
| 2026-04-10 | `eb05390` | `v0.1.0a3` | `d53d261` | Sync against BioM3-dev HEAD: bump to v0.1.0a3, add versioning guide and incident narrative correction, merge addison-spark; data-share adds VERSION file (`0.1.0a1`) and permissions reapply runbook (sticky-bit / strict ACL variants) |
| 2026-04-08 | `8c8e23c` | `v0.1.0a1` | `a14be7a` | Sync config/excludes for opting paths out of push/pull; `VERSION` file added to track data-share at `0.1.0a1`. Tested against BioM3-dev HEAD with PAD probability gauge in animations |
| 2026-04-04 | `f30d682` | — *(pre-versioning)* | `23493d5` | Current known-good state: ecosystem docs added, all Stage 1-3 weights and SH3/CM datasets compatible |

> *Pre-versioning rows refer to BioM3-dev commits before `c123efe` (2026-04-04), which introduced single-source `__version__` at `0.1.0a1`.*

## How to use this log

After generating new weights or datasets with BioM3-dev, or updating database
download/build scripts to match BioM3-dev changes:

1. Add a new row at the top of the table
2. Record the BioM3-dev commit hash used to produce the data
3. Record the BioM3-dev version at that commit (read from `biom3.__version__` or check `src/biom3/__init__.py` in BioM3-dev)
4. Record the resulting data-share commit hash (fill in after committing)
5. Write a brief summary of what changed

## Checking for upstream changes

```bash
cd /path/to/BioM3-dev
git log --oneline <last-synced-commit>..HEAD
```
