# Project Context

BioM3-data-share is a shared data repository for BioM3 model weights and datasets, synced across compute clusters (ALCF Aurora, ALCF Polaris, DGX Spark) via `sync/biom3sync.sh`.

## Structure

- `data/` — model weights and datasets (not tracked by git, synced via rsync)
  - `data/weights/` — trained model weights (Facilitator, LLMs, PenCL, ProteoScribe)
  - `data/datasets/` — training data (CM, SH3, Pfam, SwissProt, etc.)
- `databases/` — downloaded reference databases (not tracked by git, not synced)
- `sync/` — sync tooling (biom3sync.sh, config, docs)
- `.logs/` — sync logs (excluded from rsync, synced via OneDrive)
- `download/` — database download scripts (NR, Pfam, SwissProt, SMART, ExPASy, BRENDA)
- `docs/` — notes and conversation logs

## Conventions

- `data/` contents are never committed to git. Only project structure and tooling are tracked.
- File permissions matter: owner-write only for project files, setgid on `data/` for group inheritance on shared machines.
- The sync script logs to `.logs/sync.log` (TSV with a `#`-prefixed header).
