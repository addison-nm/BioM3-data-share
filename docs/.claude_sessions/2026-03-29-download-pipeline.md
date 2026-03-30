# 2026-03-29 — Database download pipeline

## New download/ directory

Added `download/` with scripts for downloading six bioinformatics reference databases:
NR, Pfam, SwissProt, SMART, ExPASy Enzyme, and BRENDA.

Files added:
- `download/download_databases.sh` — main download script
- `download/verify_checksums.sh` — checksum verification against provenance ledger
- `download/README.md` — pipeline docs (databases, setup, troubleshooting)

## Key design decisions

- **Default output to `databases/`** — downloads land in the project root (gitignored), separate from `data/` which is synced via rsync.
- **Opt-in database selection (`-d`)** — use `-d pfam -d swissprot` to download specific databases. Without `-d`, all are downloaded.
- **Switched from wget to curl** — wget's `--continue` flag is silently disabled when combined with `-O`, breaking resume. curl's `-C -` works correctly with `-o`. curl is also pre-installed on macOS.
- **Clean log files** — curl progress bar (`--progress-bar`) goes to stderr (shown on terminal) while only structured `[timestamp] [LEVEL] message` lines are written to the log file.
- **Provenance tracking** — every downloaded file is recorded in `provenance.tsv` with timestamp, filename, source URL, and MD5.

## Project file updates

- `.gitignore` — added `smart_credentials.txt` and `brenda_key.txt`
- `README.md` — added Downloading Databases section
- `CLAUDE.md` — added `download/` to project structure
