# Project Context

BioM3-data-share is a shared data repository for BioM3 model weights and datasets, synced across compute clusters (ALCF Aurora, ALCF Polaris, DGX Spark) via `sync/biom3sync.sh`.

## Practices

Store session notes in docs/.claude_sessions/

## Structure

- `data/` — model weights and datasets (not tracked by git, synced via rsync)
  - `data/weights/` — trained model weights (Facilitator, LLMs, PenCL, ProteoScribe)
  - `data/datasets/` — training data (CM, SH3, Pfam, SwissProt, etc.)
- `databases/` — downloaded reference databases (not tracked by git, not synced)
- `sync/` — sync tooling (biom3sync.sh, config, docs)
- `.logs/` — sync logs (excluded from rsync, synced via OneDrive)
- `download/` — database download scripts (NR, Pfam, SwissProt, TrEMBL, SMART, ExPASy, BRENDA)
- `docs/` — notes and conversation logs

## Ecosystem context

BioM3-data-share is the shared data layer in a multi-repo ecosystem. See [docs/biom3_ecosystem.md](docs/biom3_ecosystem.md) for full details.

Related repositories:
- **BioM3-dev** — core Python library (3-stage pipeline, dataset construction, training)
- **BioM3-workflow-demo** — end-to-end demo of finetuning and generation
- **BioM3-workspace-template** — *(planned)* workspace configuration template

Machine-specific repo paths are in `.claude/repo_paths.json` (gitignored, not version controlled). This file maps repo names to absolute paths on the current machine.

## Conventions

- `data/` contents are never committed to git. Only project structure and tooling are tracked.
- File permissions matter: owner-write only for project files, setgid on `data/` for group inheritance on shared machines.
- The sync script logs to `.logs/sync.log` (TSV with a `#`-prefixed header).
