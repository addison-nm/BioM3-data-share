# BioM3-dev Sync Log

Tracks which versions of BioM3-dev produced the weights, datasets, and database
configurations stored in this repository.

| Date | BioM3-dev commit | data-share commit | Summary |
| ---- | ---------------- | ----------------- | ------- |
| 2026-04-04 | `f30d682` | `23493d5` | Current known-good state: ecosystem docs added, all Stage 1-3 weights and SH3/CM datasets compatible |

## How to use this log

After generating new weights or datasets with BioM3-dev, or updating database
download/build scripts to match BioM3-dev changes:

1. Add a new row at the top of the table
2. Record the BioM3-dev commit hash used to produce the data
3. Record the resulting data-share commit hash (fill in after committing)
4. Write a brief summary of what changed

## Checking for upstream changes

```bash
cd /path/to/BioM3-dev
git log --oneline <last-synced-commit>..HEAD
```
