# 2026-03-30 — Add NCBI Taxonomy download and credentials directory

## Context

Need taxonomic classification data (lineages, taxon IDs) and protein-to-taxid mappings for annotating protein sequences from NR with full taxonomic lineage information. This supports downstream use cases like Diamond database construction with taxonomy-aware search.

Additionally, credential files (SMART, BRENDA) were previously expected in the working directory with no dedicated home. Moved them into a gitignored `download/credentials/` directory with a tracked README.

## Changes

### New files

- `download/credentials/.gitkeep` — ensures the directory is tracked by git
- `download/credentials/README.md` — setup instructions for SMART and BRENDA credentials, including SHA-256 hashing for BRENDA and a security checklist

### Files modified

- `download/download_databases.sh`
  - Added `ncbi_taxonomy` to `ALL_DBS` and case dispatch
  - Added `download_ncbi_taxonomy()` function (enhanced taxdump + accession-to-taxid mapping)
  - Added `CRED_DIR` variable; SMART and BRENDA functions now read credentials from `credentials/` instead of the working directory
  - Updated header comments for new database and credential paths
- `download/README.md`
  - Added NCBI Taxonomy to overview table and new section 7 with file descriptions, citation, reproducibility notes, and Diamond integration example
  - Updated all credential file paths to `download/credentials/`
  - Updated output structure tree and disk space estimate (450 GB → 460 GB)
  - Updated security notes to reference the credentials directory
- `.gitignore` — added `download/credentials/*` with exceptions for `.gitkeep` and `README.md`

### What gets downloaded (NCBI Taxonomy)

| File | Source | Size |
|------|--------|------|
| `new_taxdump.tar.gz` | `ftp.ncbi.nlm.nih.gov/pub/taxonomy/new_taxdump/` | ~500 MB |
| `prot.accession2taxid.gz` | `ftp.ncbi.nlm.nih.gov/pub/taxonomy/accession2taxid/` | ~10 GB |

The enhanced taxdump is automatically extracted after download, producing `nodes.dmp`, `names.dmp`, `rankedlineage.dmp`, `fullnamelineage.dmp`, `taxidlineage.dmp`, `merged.dmp`, `delnodes.dmp`, `typematerial.dmp`, and `host.dmp`.

## Usage

```bash
# Download just taxonomy data
bash download_databases.sh -d ncbi_taxonomy -o ./databases
```

## Key decisions

- **Enhanced taxdump (`new_taxdump`) over standard** — the enhanced version includes pre-computed ranked lineage files, avoiding the need to traverse `nodes.dmp` manually to reconstruct lineages.
- **No auth required** — unlike SMART and BRENDA, NCBI taxonomy data is freely available without credentials.
- **Auto-extraction** — the tar.gz is extracted in-place so taxonomy files are immediately usable (e.g. by Diamond `makedb`).
- **Dedicated credentials directory** — centralizes credential files in one gitignored location rather than scattering them in the working directory. The tracked README provides setup instructions so new users can self-serve.
