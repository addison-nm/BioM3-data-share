# Project Context

BioM3-data-share is a shared data repository for BioM3 model weights and datasets, synced across compute clusters (ALCF Aurora, ALCF Polaris, DGX Spark) via `sync/biom3sync.sh`.

## Structure

- `data/` — model weights and datasets (not tracked by git, synced via rsync)
  - `data/models/` — trained model weights (Facilitator, LLMs, PenCL, ProteoScribe)
  - `data/datasets/` — training data (CM, SH3, Pfam, SwissProt, etc.)
- `sync/` — sync tooling (biom3sync.sh, config, docs)
- `.logs/` — sync logs (excluded from rsync, synced via OneDrive)
- `docs/` — notes and conversation logs

## Conventions

- `data/` contents are never committed to git. Only project structure and tooling are tracked.
- File permissions matter: owner-write only for project files, setgid on `data/` for group inheritance on shared machines.
- The sync script logs to `.logs/sync.log` (TSV with a `#`-prefixed header).
