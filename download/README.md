# Bioinformatics Database Download Pipeline

**Version:** 1.0
**Date:** 2026-03-29
**Author:** (your name / lab)

---

## Overview

This pipeline downloads eight bioinformatics databases for local use in sequence analysis, functional annotation, and enzyme research. The main script (`download_databases.sh`) handles downloading, retry logic, MD5 recording, and provenance logging. A companion script (`verify_checksums.sh`) lets you re-verify file integrity at any time.

| Database | Type | Source | Auth required? | Typical size |
|----------|------|--------|----------------|--------------|
| NR | Protein sequences (all) | NCBI FTP | No | ~300 GB compressed |
| Pfam | HMM profiles + alignments | EBI FTP | No | ~10 GB |
| SwissProt | Curated protein sequences | UniProt FTP | No | ~1 GB |
| TrEMBL | Unreviewed protein sequences | UniProt FTP | No | ~120 GB |
| SMART | Domain descriptions | EMBL | No | <1 MB |
| ExPASy Enzyme | Enzyme nomenclature | ExPASy FTP | No | ~10 MB |
| BRENDA | Enzyme function & kinetics | BRENDA SOAP | Yes (free account) | ~2 GB |
| NCBI Taxonomy | Taxonomic classification + accession mapping | NCBI FTP | No | ~11 GB |

---

## Requirements

### Software

| Tool | Minimum version | Notes |
|------|----------------|-------|
| bash | 4.0+ | Available by default on Linux; use `brew install bash` on macOS |
| wget | 1.20+ | `apt install wget` / `brew install wget` |
| md5sum or md5 | any | Pre-installed on Linux / macOS respectively |
| python3 | 3.8+ | Only required for BRENDA SOAP download |
| zeep (Python) | 4.x | `pip install zeep` — only for BRENDA SOAP |

### Disk space

Reserve at least **580 GB** of free space before running the full suite. NR alone can exceed 300 GB compressed; TrEMBL adds ~120 GB; the NCBI Taxonomy accession mapping adds ~10 GB.

---

## Quick Start

```bash
# 1. Clone or copy this directory to your machine
cd /path/to/BioM3-data-share/download

# 2. (If downloading BRENDA) create credentials file
#    BRENDA expects your password as a SHA-256 hex digest
python3 -c "import hashlib; print(hashlib.sha256(b'YOUR_BRENDA_PASSWORD').hexdigest())"
cat > download/credentials/brenda_key.txt <<EOF
email=YOUR_BRENDA_EMAIL
password=<SHA256_OUTPUT_FROM_ABOVE>
EOF
chmod 600 download/credentials/brenda_key.txt

# 3. Run the downloader
bash download_databases.sh -o /mnt/databases

# 4. Verify checksums after download completes
bash verify_checksums.sh /mnt/databases
```

### Downloading a subset

Use `-s <db>` (repeatable) to skip individual databases:

```bash
# Download only SwissProt and Pfam
bash download_databases.sh -o /mnt/databases -s nr -s smart -s expasy -s brenda
```

---

## Database-by-Database Notes

### 1. NR — NCBI Non-Redundant Protein Sequences

**URL pattern:** `https://ftp.ncbi.nlm.nih.gov/blast/db/FASTA/nr.NN.gz`

NR is the broadest NCBI protein database, combining sequences from GenBank CDS translations, PDB, SwissProt, PIR, and PRF. It is split into numbered volume files (`nr.00.gz`, `nr.01.gz`, …). The script probes for each volume and stops when no further files exist.

**Citation / Attribution:**
NCBI Resource Coordinators. Database resources of the National Center for Biotechnology Information. *Nucleic Acids Res.* (annual update). https://www.ncbi.nlm.nih.gov/

**Reproducibility note:** NR is updated continuously. Record the download date (logged automatically in `provenance.tsv`) to ensure reproducibility. For a stable snapshot, consider using the BLAST pre-formatted database volumes, or archive the raw FASTA volumes you downloaded.

---

### 2. Pfam — Protein Families Database

**URL base:** `https://ftp.ebi.ac.uk/pub/databases/Pfam/current_release/`

Files downloaded:

| File | Contents |
|------|----------|
| `Pfam-A.hmm.gz` | Profile HMMs for all Pfam-A families (use with HMMER) |
| `Pfam-A.fasta.gz` | Seed sequences for each family |
| `Pfam-A.full.gz` | Full-length sequence alignments |
| `relnotes.txt` | Release version and date |

**Citation:** Mistry et al., *Nucleic Acids Res.* 2021, Pfam: The protein families database in 2021.

**Reproducibility note:** Check `relnotes.txt` for the Pfam release number (e.g., `Pfam 36.0`). The FTP `current_release/` path always points to the newest version; archived releases are available under `../releases/PfamNN/`.

---

### 3. SwissProt — UniProtKB/Swiss-Prot

**URL base:** `https://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/complete/`

Files downloaded:

| File | Contents |
|------|----------|
| `uniprot_sprot.fasta.gz` | FASTA sequences (reviewed entries only) |
| `uniprot_sprot.dat.gz` | Full flat-file with annotations, GO terms, cross-refs |
| `reldate.txt` | Release number and date |

**Citation:** The UniProt Consortium. UniProt: the universal protein knowledgebase in 2023. *Nucleic Acids Res.* 2023.

**Reproducibility note:** Record the release date in `reldate.txt`. Archived releases are available at `https://ftp.uniprot.org/pub/databases/uniprot/previous_releases/`.

---

### 4. TrEMBL — UniProtKB/TrEMBL (Unreviewed)

**URL base:** `https://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/complete/`

TrEMBL contains computationally analysed protein entries that have not yet been manually reviewed by UniProt curators. It is significantly larger than Swiss-Prot and covers a much broader set of organisms and sequences.

Files downloaded:

| File | Contents |
|------|----------|
| `uniprot_trembl.fasta.gz` | FASTA sequences (unreviewed entries) |
| `uniprot_trembl.dat.gz` | Full flat-file with annotations, GO terms, cross-refs |
| `reldate.txt` | Release number and date |

**Citation:** The UniProt Consortium. UniProt: the universal protein knowledgebase in 2023. *Nucleic Acids Res.* 2023.

**Reproducibility note:** Record the release date in `reldate.txt`. Archived releases are available at `https://ftp.uniprot.org/pub/databases/uniprot/previous_releases/`.

---

### 5. SMART — Simple Modular Architecture Research Tool

**URL:** `https://smart.embl.de/smart/descriptions.pl`

SMART provides domain annotations for signalling and extracellular domain families. The domain descriptions file (accessions, names, and functional descriptions) is publicly available with no registration required.

Files downloaded:

| File | Contents |
|------|----------|
| `SMART_domains.txt` | Domain accessions, names, and descriptions |

**Citation:** Letunic & Bork. *Nucleic Acids Res.* 2023, SMART: expanding the functional annotation of proteins.

---

### 6. ExPASy Enzyme Nomenclature Database

**URL base:** `https://ftp.expasy.org/databases/enzyme/`

ExPASy is the Swiss Institute of Bioinformatics' bioinformatics resource portal. This pipeline downloads the **ENZYME** nomenclature database, which provides standardised descriptions of enzyme reactions following the NC-IUBMB classification.

Files downloaded:

| File | Contents |
|------|----------|
| `enzyme.dat` | Full flat-file with EC numbers, reaction descriptions, synonyms |
| `enzyme.rdf` | RDF/OWL semantic version |
| `enzuser.txt` | User guide and format description |

**Citation:** Morgat et al. *Nucleic Acids Res.* 2017, Updates in Rhea—an expert curated resource of biochemical reactions.

**Reproducibility note:** The database is versioned by release date inside `enzyme.dat`. The download timestamp in `provenance.tsv` is sufficient for most purposes.

---

### 7. BRENDA — Braunschweig Enzyme Database

**URL:** `https://www.brenda-enzymes.org/`

BRENDA is a comprehensive enzyme information system with kinetic parameters, organism data, substrates, and literature. Full database access requires a **free registered account**.

**Setup:**
1. Register at https://www.brenda-enzymes.org/register.php (free).
2. Compute the SHA-256 hash of your password (see Quick Start).
3. Add credentials to `download/credentials/brenda_key.txt`.
4. The script uses the BRENDA SOAP API via the `zeep` Python library.
5. The full flat-file dump (`brenda_download.txt.gz`) can also be downloaded manually from https://www.brenda-enzymes.org/download_brenda_without_license.php after login.

**BRENDA license:** Free for academic use. Commercial use requires a separate licence. See https://www.brenda-enzymes.org/download.php.

**Citation:** Jeske et al. *Nucleic Acids Res.* 2019, BRENDA in 2019: a European ELIXIR core data resource.

---

### 8. NCBI Taxonomy — Taxonomic Classification & Protein Mapping

**URL bases:**
- `https://ftp.ncbi.nlm.nih.gov/pub/taxonomy/new_taxdump/`
- `https://ftp.ncbi.nlm.nih.gov/pub/taxonomy/accession2taxid/`

The NCBI Taxonomy database provides the hierarchical taxonomic tree and maps protein accessions to taxonomy IDs, enabling taxonomic lineage annotation of protein sequences (e.g. for the NR database).

Files downloaded:

| File | Contents |
|------|----------|
| `new_taxdump.tar.gz` | Enhanced taxonomy dump (extracted automatically) |
| `prot.accession2taxid.gz` | Protein accession → taxonomy ID mapping (~10 GB) |

**Extracted taxonomy files** (from `new_taxdump.tar.gz`):

| File | Contents |
|------|----------|
| `nodes.dmp` | Taxonomic tree structure (parent-child relationships, ranks) |
| `names.dmp` | Taxonomic names and synonyms |
| `rankedlineage.dmp` | Complete ranked lineage for each taxid |
| `fullnamelineage.dmp` | Full name lineage strings |
| `taxidlineage.dmp` | Taxid-based lineage |
| `merged.dmp` | Merged (deprecated) taxonomy IDs |
| `delnodes.dmp` | Deleted nodes |
| `typematerial.dmp` | Type material information |
| `host.dmp` | Host organism information |

**Citation:** Schoch et al., *Database* 2020, NCBI Taxonomy: a comprehensive update on curation, resources and tools.

**Reproducibility note:** Taxonomy data is updated as new organisms are added. Record the download timestamp from `provenance.tsv`. For Diamond database construction, combine `nodes.dmp` and `names.dmp` from this download with the NR FASTA and `prot.accession2taxid.gz`.

**Diamond integration:**
```bash
diamond makedb --in nr.faa --db nr \
    --taxonmap ncbi_taxonomy/prot.accession2taxid.gz \
    --taxonnodes ncbi_taxonomy/nodes.dmp \
    --taxonnames ncbi_taxonomy/names.dmp
```

---

## Output Structure

After a full run, the output directory will look like this:

```
databases/
├── provenance.tsv          — master ledger: timestamp, filename, URL, MD5
├── nr/
│   ├── nr.00.gz
│   ├── nr.01.gz
│   └── ...
├── pfam/
│   ├── Pfam-A.hmm.gz
│   ├── Pfam-A.fasta.gz
│   ├── Pfam-A.full.gz
│   └── relnotes.txt
├── swissprot/
│   ├── uniprot_sprot.fasta.gz
│   ├── uniprot_sprot.dat.gz
│   └── reldate.txt
├── trembl/
│   ├── uniprot_trembl.fasta.gz
│   ├── uniprot_trembl.dat.gz
│   └── reldate.txt
├── smart/
│   └── SMART_domains.txt
├── expasy/
│   ├── enzyme.dat
│   ├── enzyme.rdf
│   └── enzuser.txt
├── brenda/
│   └── brenda_download_YYYYMMDD.txt
└── ncbi_taxonomy/
    ├── new_taxdump.tar.gz
    ├── prot.accession2taxid.gz
    ├── nodes.dmp
    ├── names.dmp
    ├── rankedlineage.dmp
    ├── fullnamelineage.dmp
    ├── taxidlineage.dmp
    ├── merged.dmp
    ├── delnodes.dmp
    ├── typematerial.dmp
    └── host.dmp
```

### provenance.tsv format

```
download_timestamp        filename                  source_url                  md5
2026-03-29T14:02:11Z      uniprot_sprot.fasta.gz    https://ftp.uniprot.org/…   d41d8cd98f00b204e9800998ecf8427e
```

---

## Reproducibility Checklist

- [ ] `provenance.tsv` committed to version control (without credential files)
- [ ] Release version recorded for Pfam (`relnotes.txt`), SwissProt (`reldate.txt`), and TrEMBL (`reldate.txt`)
- [ ] Download date recorded (automatic in `provenance.tsv`)
- [ ] `verify_checksums.sh` run and passed after download
- [ ] SMART and BRENDA credential files **not** committed to version control (add to `.gitignore`)
- [ ] Compute environment (OS, wget version) documented in your lab notebook

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `wget: command not found` | wget not installed | `apt install wget` or `brew install wget` |
| NR download stalls at volume 00 | FTP firewall/proxy | Try `-j 1`; check your institution's FTP access |
| SMART login fails | Wrong credentials or site change | Check https://smart.embl.de/ manually |
| BRENDA SOAP error | `zeep` not installed or API changed | `pip install zeep`; check BRENDA SOAP WSDL at their website |
| MD5 mismatch | Interrupted download | Delete the partial file, re-run; `wget --continue` will resume |
| Disk full mid-download | Insufficient space | Free space, then re-run — wget `--continue` resumes incomplete files |

---

## Security Notes

- Credential files live in `download/credentials/`, which is gitignored (only the `.gitkeep` and `README.md` are tracked). Set file permissions to `600`.
- BRENDA stores the password as a SHA-256 hex digest over the SOAP API; do not store your plain-text password anywhere in this repository.
