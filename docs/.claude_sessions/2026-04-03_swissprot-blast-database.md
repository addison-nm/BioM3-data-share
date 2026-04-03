# Session: Add SwissProt BLAST Database Support

**Date:** 2026-04-03
**Pre-session state:** `git checkout a875985`

## Summary

Added a `swissprot_blast` option to the database download pipeline that builds a local BLAST protein database from the SwissProt (UniProtKB/Swiss-Prot) FASTA sequences using `makeblastdb`. This enables running `blastp` searches against the curated SwissProt dataset.

## Changes

### `download/download_databases.sh`

- Added `swissprot_blast` to the `ALL_DBS` array, usage header, requirements comment, and `case` dispatch block.
- Added `download_swissprot_blast()` function that:
  - Checks that `makeblastdb` (BLAST+ suite) is on PATH; exits with install instructions if not.
  - Reuses `databases/swissprot/uniprot_sprot.fasta.gz` if a prior `swissprot` download exists; otherwise downloads the FASTA fresh from UniProt FTP.
  - Decompresses and runs `makeblastdb -in ... -dbtype prot -parse_seqids -title "UniProtKB/Swiss-Prot" -out swissprot`.
  - Validates that index files were created and appends a provenance record.
  - Prints a usage hint with the `blastp` command.

### `download/README.md`

- Added SwissProt BLAST row to the overview table.
- Added `makeblastdb` to the software requirements table.
- Added section 3b documenting the SwissProt BLAST database (output files, usage example).
- Added `swissprot_blast/` to the output directory structure diagram.

## Design Decisions

- **Local `makeblastdb` build vs pre-formatted download:** Unlike NCBI NR (which distributes pre-formatted BLAST volumes), SwissProt is small enough (~90 MB compressed FASTA, ~300 MB formatted DB) that building locally is fast and avoids dependency on a pre-formatted distribution that doesn't exist.
- **Reuse existing FASTA:** If the user has already run `-d swissprot`, the FASTA is copied rather than re-downloaded, saving time and bandwidth.
- **Separate output directory:** `databases/swissprot_blast/` keeps the BLAST index files separate from the raw SwissProt data in `databases/swissprot/`, consistent with the `nr` vs `nr_blast` pattern.

## Usage

```bash
# Build the SwissProt BLAST database
bash download_databases.sh -d swissprot_blast

# Search against it
blastp -db databases/swissprot_blast/swissprot -query input.fasta -out results.txt
```
