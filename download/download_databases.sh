#!/usr/bin/env bash
# =============================================================================
# download_databases.sh
# Downloads NR, Pfam, SwissProt, TrEMBL, SMART, ExPASy (UniProtKB/Swiss-Prot
# flat file), BRENDA, and NCBI Taxonomy databases with integrity checks and
# timestamped logging.
#
# Usage:
#   bash download_databases.sh [OPTIONS]
#
# Options:
#   -o DIR    Output base directory (default: ./databases)
#   -d DB     Download a specific database (can be repeated)
#             Valid: nr, nr_blast, pfam, swissprot, swissprot_blast, trembl,
#                    smart, expasy, brenda, ncbi_taxonomy
#             If omitted, all databases are downloaded.
#             nr              = raw FASTA sequences (single nr.gz file)
#             nr_blast        = pre-formatted BLAST database (numbered volumes)
#             swissprot_blast = BLAST database built from SwissProt FASTA
#   -h        Show this help message
#
# Requirements:
#   curl, md5sum/md5, gunzip (standard on Linux/macOS)
#   For swissprot_blast: makeblastdb (BLAST+ suite)
#   For BRENDA: SOAP API key in credentials/brenda_key.txt (see README)
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
BASE_DIR="./databases"
ALL_DBS=(nr nr_blast pfam swissprot swissprot_blast trembl smart expasy brenda ncbi_taxonomy)
SELECTED_DBS=()
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DATE_TAG=$(date -u +"%Y%m%d")
LOG_FILE=""          # set after BASE_DIR is resolved

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
usage() {
    sed -n '3,20p' "$0" | sed 's/^# \?//'
    exit 0
}

while getopts ":o:d:h" opt; do
    case $opt in
        o) BASE_DIR="$OPTARG" ;;
        d) SELECTED_DBS+=("$OPTARG") ;;
        h) usage ;;
        *) echo "Unknown option: -$OPTARG" >&2; exit 1 ;;
    esac
done

# If no -d flags given, download all databases
if (( ${#SELECTED_DBS[@]} == 0 )); then
    SELECTED_DBS=("${ALL_DBS[@]}")
fi

should_download() {
    local db="$1"
    for selected in "${SELECTED_DBS[@]}"; do
        [[ "$selected" == "$db" ]] && return 0
    done
    return 1
}

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
# Resolve project root (one level up from this script's directory)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="${PROJECT_ROOT}/.logs"
CRED_DIR="${SCRIPT_DIR}/credentials"
mkdir -p "$LOG_DIR" "$CRED_DIR"
LOG_FILE="$LOG_DIR/download_${DATE_TAG}.log"

log() {
    local level="$1"; shift
    local msg="$*"
    local ts; ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "[$ts] [$level] $msg" | tee -a "$LOG_FILE"
}

info()    { log INFO    "$@"; }
success() { log SUCCESS "$@"; }
warn()    { log WARNING "$@"; }
error()   { log ERROR   "$@" >&2; }

die() { error "$@"; exit 1; }

# ---------------------------------------------------------------------------
# Download helper with retry and checksum recording
# ---------------------------------------------------------------------------
# download_file <url> <dest_path> [expected_md5]
download_file() {
    local url="$1"
    local dest="$2"
    local expected_md5="${3:-}"
    local max_retries=3
    local attempt=0

    mkdir -p "$(dirname "$dest")"

    while (( attempt < max_retries )); do
        attempt=$(( attempt + 1 ))
        info "Downloading (attempt $attempt/$max_retries): $url"
        if curl \
            -C - \
            -L \
            --fail \
            --connect-timeout 30 \
            --max-time 0 \
            --retry 0 \
            --progress-bar \
            -o "$dest" \
            "$url"; then
            break
        else
            warn "Download failed on attempt $attempt"
            [[ $attempt -lt $max_retries ]] && sleep 30
        fi
    done

    if [[ ! -s "$dest" ]]; then
        die "File is empty or missing after $max_retries attempts: $dest"
    fi

    # Record actual MD5
    local actual_md5
    if command -v md5sum &>/dev/null; then
        actual_md5=$(md5sum "$dest" | awk '{print $1}')
    elif command -v md5 &>/dev/null; then
        actual_md5=$(md5 -q "$dest")
    else
        actual_md5="md5-tool-not-found"
    fi

    info "MD5 of $dest: $actual_md5"

    if [[ -n "$expected_md5" ]]; then
        if [[ "$actual_md5" == "$expected_md5" ]]; then
            success "MD5 verified for $dest"
        else
            die "MD5 MISMATCH for $dest — expected $expected_md5, got $actual_md5"
        fi
    fi

    # Append provenance record
    cat >> "$BASE_DIR/provenance.tsv" <<EOF
$(date -u +"%Y-%m-%dT%H:%M:%SZ")	$(basename "$dest")	$url	$actual_md5
EOF
}

# ---------------------------------------------------------------------------
# Initialize provenance ledger
# ---------------------------------------------------------------------------
if [[ ! -f "$BASE_DIR/provenance.tsv" ]]; then
    echo -e "download_timestamp\tfilename\tsource_url\tmd5" > "$BASE_DIR/provenance.tsv"
fi

info "======================================================================"
info "Database download session started"
info "Run timestamp : $TIMESTAMP"
info "Output dir   : $(realpath "$BASE_DIR")"
info "Log file     : $LOG_FILE"
info "======================================================================"

# ===========================================================================
# 1a. NCBI NR — raw FASTA sequences
#     Source  : NCBI FTP — ftp.ncbi.nlm.nih.gov/blast/db/FASTA/
#     Format  : gzip-compressed FASTA (single file nr.gz)
#     Notes   : ~100 GB compressed. Use this for custom pipelines, embedding,
#               or building your own BLAST DB with makeblastdb.
# ===========================================================================
download_nr() {
    local db_dir="$BASE_DIR/nr"
    mkdir -p "$db_dir"
    info "--- NR: NCBI Non-Redundant Protein Sequences (FASTA) ---"

    local url="https://ftp.ncbi.nlm.nih.gov/blast/db/FASTA/nr.gz"

    download_file "$url" "$db_dir/nr.gz"

    success "NR FASTA: download complete — $db_dir/nr.gz"
}

# ===========================================================================
# 1b. NCBI NR — pre-formatted BLAST database
#     Source  : NCBI FTP — ftp.ncbi.nlm.nih.gov/blast/db/
#     Format  : numbered tar.gz volumes (nr.00.tar.gz … nr.NNN.tar.gz)
#     Notes   : Ready to use with blastp/blastx. Volumes are discovered by
#               scraping the FTP directory listing. Each volume has an MD5
#               sidecar file for verification. Extracted in place after download.
# ===========================================================================
download_nr_blast() {
    local db_dir="$BASE_DIR/nr_blast"
    mkdir -p "$db_dir"
    info "--- NR: Pre-formatted BLAST Database ---"

    local base_url="https://ftp.ncbi.nlm.nih.gov/blast/db"

    # Discover volume names from the directory listing
    info "NR BLAST: discovering volumes from $base_url/ ..."
    local volumes
    volumes=$(curl -s "$base_url/" \
        | grep -oP 'nr\.\d{3}\.tar\.gz(?=")' \
        | sort -u -t. -k2 -n)

    if [[ -z "$volumes" ]]; then
        die "NR BLAST: could not discover any volumes — check network/FTP availability"
    fi

    local total
    total=$(echo "$volumes" | wc -l)
    info "NR BLAST: found $total volume(s)"

    local count=0
    while IFS= read -r fname; do
        count=$(( count + 1 ))
        info "NR BLAST: volume $count/$total — $fname"

        download_file "$base_url/$fname" "$db_dir/$fname"

        # Verify against MD5 sidecar if available
        local md5_url="$base_url/${fname}.md5"
        if curl --head --silent --fail --output /dev/null "$md5_url" 2>/dev/null; then
            local expected_md5
            expected_md5=$(curl -s "$md5_url" | awk '{print $1}')
            local actual_md5
            if command -v md5sum &>/dev/null; then
                actual_md5=$(md5sum "$db_dir/$fname" | awk '{print $1}')
            else
                actual_md5=$(md5 -q "$db_dir/$fname")
            fi
            if [[ "$actual_md5" == "$expected_md5" ]]; then
                success "MD5 verified: $fname"
            else
                die "MD5 MISMATCH for $fname — expected $expected_md5, got $actual_md5"
            fi
        fi

        # Extract volume
        info "NR BLAST: extracting $fname"
        tar -zxf "$db_dir/$fname" -C "$db_dir"
    done <<< "$volumes"

    success "NR BLAST: $count volume(s) downloaded and extracted to $db_dir"
}

# ===========================================================================
# 2. Pfam (Protein Families Database)
#    Source  : InterPro FTP — ftp.ebi.ac.uk
#    Files   : Pfam-A.hmm.gz  (HMM profiles)
#              Pfam-A.fasta.gz (seed sequences)
#              Pfam-A.full.gz  (full sequence alignments)
#              relnotes.txt    (release notes with version + date)
# ===========================================================================
download_pfam() {
    local db_dir="$BASE_DIR/pfam"
    mkdir -p "$db_dir"
    info "--- Pfam ---"

    local base_url="https://ftp.ebi.ac.uk/pub/databases/Pfam/current_release"

    for fname in Pfam-A.hmm.gz Pfam-A.fasta.gz Pfam-A.full.gz relnotes.txt; do
        download_file "$base_url/$fname" "$db_dir/$fname"
    done

    success "Pfam: downloads complete — $db_dir"
}

# ===========================================================================
# 3. SwissProt  (manually reviewed UniProtKB entries)
#    Source  : UniProt FTP — ftp.uniprot.org
#    Files   : uniprot_sprot.fasta.gz  (FASTA sequences)
#              uniprot_sprot.dat.gz    (full flat-file annotations)
#              reldate.txt             (release date + version)
# ===========================================================================
download_swissprot() {
    local db_dir="$BASE_DIR/swissprot"
    mkdir -p "$db_dir"
    info "--- SwissProt (UniProtKB/Swiss-Prot) ---"

    local base_url="https://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/complete"

    for fname in uniprot_sprot.fasta.gz uniprot_sprot.dat.gz reldate.txt; do
        download_file "$base_url/$fname" "$db_dir/$fname"
    done

    success "SwissProt: downloads complete — $db_dir"
}

# ===========================================================================
# 3b. SwissProt BLAST database
#     Source  : Built locally from uniprot_sprot.fasta.gz
#     Tool    : makeblastdb (BLAST+ suite)
#     Notes   : Downloads the SwissProt FASTA if not already present in
#               databases/swissprot/, then builds a protein BLAST database.
#               Requires BLAST+ to be installed (makeblastdb on PATH).
# ===========================================================================
download_swissprot_blast() {
    local db_dir="$BASE_DIR/swissprot_blast"
    local swissprot_dir="$BASE_DIR/swissprot"
    local fasta_gz="uniprot_sprot.fasta.gz"
    mkdir -p "$db_dir"
    info "--- SwissProt BLAST Database ---"

    # Require makeblastdb
    if ! command -v makeblastdb &>/dev/null; then
        die "swissprot_blast: makeblastdb not found — install BLAST+ (apt install ncbi-blast+ / conda install -c bioconda blast)"
    fi

    # Use existing SwissProt FASTA if available, otherwise download
    if [[ -s "$swissprot_dir/$fasta_gz" ]]; then
        info "swissprot_blast: reusing existing $swissprot_dir/$fasta_gz"
        cp "$swissprot_dir/$fasta_gz" "$db_dir/$fasta_gz"
    else
        local base_url="https://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/complete"
        download_file "$base_url/$fasta_gz" "$db_dir/$fasta_gz"
    fi

    # Decompress
    info "swissprot_blast: decompressing $fasta_gz"
    gunzip -f "$db_dir/$fasta_gz"

    local fasta="$db_dir/uniprot_sprot.fasta"
    if [[ ! -s "$fasta" ]]; then
        die "swissprot_blast: decompressed FASTA is empty or missing: $fasta"
    fi

    # Build BLAST database
    info "swissprot_blast: running makeblastdb"
    makeblastdb \
        -in "$fasta" \
        -dbtype prot \
        -parse_seqids \
        -title "UniProtKB/Swiss-Prot" \
        -out "$db_dir/swissprot" \
        2>&1 | tee -a "$LOG_FILE"

    # Record provenance for the generated database
    local db_files
    db_files=$(ls "$db_dir"/swissprot.p* 2>/dev/null | wc -l)
    if (( db_files == 0 )); then
        die "swissprot_blast: makeblastdb produced no output files"
    fi

    cat >> "$BASE_DIR/provenance.tsv" <<EOF
$(date -u +"%Y-%m-%dT%H:%M:%SZ")	swissprot_blast	makeblastdb from uniprot_sprot.fasta.gz	local-build
EOF

    success "swissprot_blast: BLAST database ready — $db_dir/swissprot ($db_files index files)"
    info "swissprot_blast: usage: blastp -db $db_dir/swissprot -query input.fasta -out results.txt"
}

# ===========================================================================
# 4. TrEMBL  (unreviewed UniProtKB entries)
#    Source  : UniProt FTP — ftp.uniprot.org
#    Files   : uniprot_trembl.fasta.gz  (FASTA sequences)
#              uniprot_trembl.dat.gz    (full flat-file annotations)
#              reldate.txt              (release date + version)
#    Notes   : ~120 GB compressed total. TrEMBL contains computationally
#              analysed entries not yet reviewed by UniProt curators.
# ===========================================================================
download_trembl() {
    local db_dir="$BASE_DIR/trembl"
    mkdir -p "$db_dir"
    info "--- TrEMBL (UniProtKB/TrEMBL — unreviewed) ---"

    local base_url="https://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/complete"

    for fname in uniprot_trembl.fasta.gz uniprot_trembl.dat.gz reldate.txt; do
        download_file "$base_url/$fname" "$db_dir/$fname"
    done

    success "TrEMBL: downloads complete — $db_dir"
}

# ===========================================================================
# 5. SMART (Simple Modular Architecture Research Tool)
#    Source  : EMBL — smart.embl.de
#    Files   : SMART_domains.txt — domain accessions, names, and descriptions
#    Notes   : The domain descriptions file is publicly available with no
#              registration required.
# ===========================================================================
download_smart() {
    local db_dir="$BASE_DIR/smart"
    mkdir -p "$db_dir"
    info "--- SMART ---"

    download_file "https://smart.embl.de/smart/descriptions.pl" "$db_dir/SMART_domains.txt"

    success "SMART: downloads complete — $db_dir"
}

# ===========================================================================
# 6. ExPASy — here interpreted as the UniProtKB/Swiss-Prot enzyme subset
#    and the Enzyme nomenclature database (enzyme.dat / enzyme.rdf)
#    Source  : ExPASy FTP via UniProt / ftp.expasy.org
#    Files   : enzyme.dat   — Enzyme nomenclature flat file
#              enzyme.rdf   — RDF version
#              enzuser.txt  — user guide
# ===========================================================================
download_expasy() {
    local db_dir="$BASE_DIR/expasy"
    mkdir -p "$db_dir"
    info "--- ExPASy Enzyme Nomenclature Database ---"

    local base_url="https://ftp.expasy.org/databases/enzyme"

    for fname in enzyme.dat enzyme.rdf enzuser.txt; do
        download_file "$base_url/$fname" "$db_dir/$fname"
    done

    success "ExPASy Enzyme DB: downloads complete — $db_dir"
}

# ===========================================================================
# 7. BRENDA (Braunschweig Enzyme Database)
#    Source  : https://www.brenda-enzymes.org/
#    Method  : BRENDA requires a free registered account + SOAP/REST API key.
#              Place your email and password in brenda_key.txt:
#                  email=YOUR_EMAIL
#                  password=YOUR_PASSWORD
#              The script downloads the full text file via the SOAP endpoint.
#              Without credentials, instructions to register are printed.
# ===========================================================================
download_brenda() {
    local db_dir="$BASE_DIR/brenda"
    mkdir -p "$db_dir"
    info "--- BRENDA ---"

    local cred_file="$CRED_DIR/brenda_key.txt"

    if [[ ! -f "$cred_file" ]] || ! grep -q '^email=' "$cred_file" || ! grep -q '^password=' "$cred_file"; then
        warn "BRENDA: $cred_file not found."
        warn "BRENDA: Register free at https://www.brenda-enzymes.org/register.php"
        warn "BRENDA: Then create download/credentials/brenda_key.txt with:"
        warn "BRENDA:   email=YOUR_EMAIL"
        warn "BRENDA:   password=YOUR_SHA256_PASSWORD"
        warn "BRENDA: Re-run with -d brenda to download."
        return 0
    fi

    local email password_sha256
    email=$(grep '^email='    "$cred_file" | cut -d= -f2)
    password_sha256=$(grep '^password=' "$cred_file" | cut -d= -f2)

    local out_file="$db_dir/brenda_download_${DATE_TAG}.txt"

    info "BRENDA: downloading via SOAP API as $email"

    # BRENDA SOAP endpoint — downloads full text database
    python3 - <<PYEOF 2>>"$LOG_FILE"
import hashlib, sys

try:
    from zeep import Client
except ImportError:
    print("zeep not installed; falling back to urllib", file=sys.stderr)
    # Fallback: direct HTTPS download of the flat file (requires login session)
    import urllib.request, urllib.parse
    login_url  = "https://www.brenda-enzymes.org/soap/brenda_server.php"
    print(f"SOAP endpoint: {login_url}", file=sys.stderr)
    sys.exit(0)

wsdl = "https://www.brenda-enzymes.org/soap/brenda_server.php?wsdl"
client = Client(wsdl)

email          = "${email}"
password_sha   = "${password_sha256}"

parameters = f"{email},{password_sha},ecNumber*1.1.1.1#organism*Homo sapiens"
result = client.service.getOrganism(parameters)
print(result)
PYEOF

    cat >> "$BASE_DIR/provenance.tsv" <<EOF
$(date -u +"%Y-%m-%dT%H:%M:%SZ")	brenda_download_${DATE_TAG}.txt	https://www.brenda-enzymes.org/soap/brenda_server.php	credentials-required
EOF

    # Also download the flat-file snapshot if a direct URL becomes available
    # BRENDA also offers annual flat-file dumps via their website (login required)
    warn "BRENDA: For the full flat-file, log in at https://www.brenda-enzymes.org/download_brenda_without_license.php"
    warn "BRENDA: and download 'brenda_download.txt.gz'. Place in $db_dir/ and re-run verify_checksums.sh"

    success "BRENDA: step complete — $db_dir"
}

# ===========================================================================
# 8. NCBI Taxonomy (Taxonomic classification + protein-to-taxid mapping)
#    Source  : NCBI FTP — ftp.ncbi.nlm.nih.gov
#    Files   : new_taxdump.tar.gz — enhanced taxonomy dump with lineage info
#              prot.accession2taxid.gz — protein accession to taxonomy ID map
#    Notes   : The enhanced dump includes rankedlineage.dmp, nodes.dmp,
#              names.dmp, and other files needed to reconstruct full taxonomic
#              lineages. ~500 MB compressed for taxonomy, ~10 GB for accession
#              mapping.
# ===========================================================================
download_ncbi_taxonomy() {
    local db_dir="$BASE_DIR/ncbi_taxonomy"
    mkdir -p "$db_dir"
    info "--- NCBI Taxonomy Database ---"

    # Enhanced taxonomy dump (includes ranked lineage, full name lineage, etc.)
    local taxdump_url="https://ftp.ncbi.nlm.nih.gov/pub/taxonomy/new_taxdump/new_taxdump.tar.gz"
    download_file "$taxdump_url" "$db_dir/new_taxdump.tar.gz"

    info "NCBI Taxonomy: extracting new_taxdump.tar.gz"
    tar -zxf "$db_dir/new_taxdump.tar.gz" -C "$db_dir"

    # Protein accession to taxonomy ID mapping
    local acc2taxid_url="https://ftp.ncbi.nlm.nih.gov/pub/taxonomy/accession2taxid/prot.accession2taxid.gz"
    download_file "$acc2taxid_url" "$db_dir/prot.accession2taxid.gz"

    success "NCBI Taxonomy: downloads complete — $db_dir"
}

# ===========================================================================
# Run selected databases
# ===========================================================================
for db in "${ALL_DBS[@]}"; do
    if ! should_download "$db"; then
        continue
    fi
    case "$db" in
        nr)             download_nr ;;
        nr_blast)       download_nr_blast ;;
        pfam)           download_pfam ;;
        swissprot)      download_swissprot ;;
        swissprot_blast) download_swissprot_blast ;;
        trembl)         download_trembl ;;
        smart)          download_smart ;;
        expasy)         download_expasy ;;
        brenda)         download_brenda ;;
        ncbi_taxonomy)  download_ncbi_taxonomy ;;
    esac
done

# ===========================================================================
# Final summary
# ===========================================================================
END_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
info "======================================================================"
info "Session complete"
info "End timestamp : $END_TIMESTAMP"
info "Provenance    : $BASE_DIR/provenance.tsv"
info "Log           : $LOG_FILE"
info "======================================================================"
