# 2026-03-31 — Fix NR database download and add BLAST DB option

## Context

Running `download_databases.sh -d nr` downloaded zero files. The script assumed NR was distributed as numbered FASTA volumes (`nr.00.gz`, `nr.01.gz`, ...) at the NCBI `/blast/db/FASTA/` endpoint. In reality, that endpoint serves a single `nr.gz` file. The volume-based loop probed for `nr.00.gz`, got a 404, and exited immediately with "no volumes downloaded."

Separately, NCBI does distribute NR as numbered volumes — but those are pre-formatted BLAST databases (`nr.000.tar.gz`, ...) at a different endpoint (`/blast/db/`), not raw FASTA. The user needs both formats: raw FASTA for custom pipelines and the BLAST DB for running `blastp`/`blastx` searches.

A second issue was discovered when testing the BLAST DB download: NCBI's `/blast/db/` directory listing contains stale 2-digit entries (`nr.00.tar.gz`, `nr.01.tar.gz`, `nr.02.tar.gz`) that return 404. Without `--fail`, `curl` silently saved the HTML error page as the output file, which then failed on `tar -zxf` ("not in gzip format").

## Changes

### Files modified

- `download/download_databases.sh`
  - Split NR into two database options: `nr` (raw FASTA, single `nr.gz` from `/blast/db/FASTA/`) and `nr_blast` (pre-formatted BLAST DB volumes from `/blast/db/`)
  - `nr_blast` discovers volumes by scraping the FTP directory listing; regex narrowed from `\d+` to `\d{3}` to skip stale 2-digit entries
  - Each BLAST DB volume is verified against its `.md5` sidecar file and extracted after download
  - Added `--fail` flag to `curl` in `download_file()` so HTTP errors cause a retry/failure instead of silently saving error pages
  - Updated help text and `ALL_DBS` array to include `nr_blast`

## Key decisions

- **Two separate options rather than replacing one** — `nr` and `nr_blast` serve different purposes and download to separate directories (`databases/nr/` and `databases/nr_blast/`). Both are included in a full download (no `-d` flag).
- **Scrape directory listing rather than incrementing volume numbers** — NCBI's numbering has gaps and mixed digit widths; scraping is more robust than guessing.
- **`--fail` added globally to `download_file()`** — benefits all database downloads, not just NR. Prevents silent corruption from saved error pages.
