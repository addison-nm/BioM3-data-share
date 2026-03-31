# Add TrEMBL (unreviewed UniProt) to download pipeline

**Date:** 2026-03-31

## Summary

Added TrEMBL (UniProtKB/TrEMBL) as database #4 in the download pipeline.
TrEMBL contains computationally analysed, unreviewed protein entries — the
complement of the already-supported SwissProt (reviewed entries).

## Files changed

- `download/download_databases.sh` — added `download_trembl()` function,
  `trembl` to `ALL_DBS` array and dispatch `case`, renumbered sections 4-7 to
  5-8.
- `download/README.md` — added TrEMBL to overview table, disk space estimate
  (460 -> 580 GB), new section 4 with file table/citation/reproducibility note,
  output structure tree, and reproducibility checklist. Renumbered sections 4-7
  to 5-8.
- `CLAUDE.md` — added TrEMBL to the `download/` description line.

## Details

- **Source:** UniProt FTP (`ftp.uniprot.org`), same base URL as SwissProt.
- **Files downloaded:**
  - `uniprot_trembl.fasta.gz` — FASTA sequences (~90 GB compressed)
  - `uniprot_trembl.dat.gz` — full flat-file annotations (~30 GB compressed)
  - `reldate.txt` — release version
- **Estimated size:** ~120 GB compressed total.
- **Usage:** `bash download_databases.sh -d trembl -o ./databases`
