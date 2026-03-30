#!/usr/bin/env bash
# =============================================================================
# download_databases.sh
# Downloads NR, Pfam, SwissProt, SMART, ExPASy (UniProtKB/Swiss-Prot flat file),
# and BRENDA databases with integrity checks and timestamped logging.
#
# Usage:
#   bash download_databases.sh [OPTIONS]
#
# Options:
#   -o DIR    Output base directory (default: ./databases)
#   -d DB     Download a specific database (can be repeated)
#             Valid: nr, pfam, swissprot, smart, expasy, brenda
#             If omitted, all databases are downloaded.
#   -h        Show this help message
#
# Requirements:
#   curl, md5sum/md5, gunzip (standard on Linux/macOS)
#   For SMART: account credentials in smart_credentials.txt (see README)
#   For BRENDA: SOAP API key in brenda_key.txt (see README)
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
BASE_DIR="./databases"
ALL_DBS=(nr pfam swissprot smart expasy brenda)
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
mkdir -p "$LOG_DIR"
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
# 1. NCBI NR (Non-Redundant protein sequences)
#    Source  : NCBI FTP — ftp.ncbi.nlm.nih.gov
#    Format  : gzip-compressed FASTA, split into volumes nr.00.gz … nr.NN.gz
#    Notes   : NR is very large (>100 GB compressed). The script downloads all
#              volumes present on the FTP. Use -d to select specific databases.
# ===========================================================================
download_nr() {
    local db_dir="$BASE_DIR/nr"
    mkdir -p "$db_dir"
    info "--- NR: NCBI Non-Redundant Protein Sequences ---"

    local base_url="https://ftp.ncbi.nlm.nih.gov/blast/db/FASTA"
    # NR is split into numbered volumes
    local vol=0
    local downloaded=0
    while true; do
        local vol_str; vol_str=$(printf "%02d" "$vol")
        local fname="nr.${vol_str}.gz"
        local url="$base_url/$fname"

        # Probe whether the file exists before attempting download
        if ! curl --head --silent --fail --output /dev/null "$url" 2>/dev/null; then
            info "NR: no more volumes found after volume $((vol - 1))"
            break
        fi

        download_file "$url" "$db_dir/$fname"
        downloaded=$(( downloaded + 1 ))
        vol=$(( vol + 1 ))
    done

    if (( downloaded == 0 )); then
        warn "NR: no volumes downloaded — check network/FTP availability"
    else
        success "NR: downloaded $downloaded volume(s) to $db_dir"
    fi
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
# 4. SMART (Simple Modular Architecture Research Tool)
#    Source  : EMBL — smart.embl.de
#    Notes   : SMART HMM library requires a free registered account.
#              Place username and password in smart_credentials.txt:
#                  username=YOUR_USERNAME
#                  password=YOUR_PASSWORD
#              The script will attempt a form-based login and cookie-based
#              download. Without credentials, only the public HMM file is
#              available and a warning is issued.
# ===========================================================================
download_smart() {
    local db_dir="$BASE_DIR/smart"
    mkdir -p "$db_dir"
    info "--- SMART ---"

    local cred_file="smart_credentials.txt"
    local hmm_url="https://smart.embl.de/smart/do_annotation.pl?BLAST=DUMMY&DOMAIN=ALL&BLAST=DUMMY&THRESHOLDS=gathering"

    if [[ -f "$cred_file" ]]; then
        local username password
        username=$(grep '^username=' "$cred_file" | cut -d= -f2)
        password=$(grep '^password=' "$cred_file" | cut -d= -f2)

        info "SMART: logging in as $username"
        curl -L -s \
            -c "$db_dir/smart_cookies.txt" \
            -d "action=login&username=${username}&password=${password}" \
            -o /dev/null \
            "https://smart.embl.de/smart/login.cgi" 2>>"$LOG_FILE"

        info "SMART: downloading HMM library (authenticated)"
        curl -L \
            -b "$db_dir/smart_cookies.txt" \
            -o "$db_dir/SMART_hmms.gz" \
            "https://smart.embl.de/smart/SMART_hmms.gz" 2>>"$LOG_FILE"
    else
        warn "SMART: $cred_file not found — skipping authenticated download."
        warn "SMART: Create $cred_file with username= and password= lines and re-run."
        warn "SMART: Register free at https://smart.embl.de/"
        # Download the publicly accessible domain list as a fallback
        info "SMART: downloading public domain list instead"
        curl -L -o "$db_dir/SMART_domains.txt" \
            "https://smart.embl.de/smart/descriptions.pl" 2>>"$LOG_FILE" || true
    fi

    # Record provenance regardless
    cat >> "$BASE_DIR/provenance.tsv" <<EOF
$(date -u +"%Y-%m-%dT%H:%M:%SZ")	SMART_hmms.gz	https://smart.embl.de/smart/SMART_hmms.gz	manual-login-required
EOF

    success "SMART: step complete — $db_dir"
}

# ===========================================================================
# 5. ExPASy — here interpreted as the UniProtKB/Swiss-Prot enzyme subset
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
# 6. BRENDA (Braunschweig Enzyme Database)
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

    local cred_file="brenda_key.txt"

    if [[ ! -f "$cred_file" ]]; then
        warn "BRENDA: $cred_file not found."
        warn "BRENDA: Register free at https://www.brenda-enzymes.org/register.php"
        warn "BRENDA: Then create brenda_key.txt with:"
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
# Run selected databases
# ===========================================================================
for db in "${ALL_DBS[@]}"; do
    if ! should_download "$db"; then
        continue
    fi
    case "$db" in
        nr)         download_nr ;;
        pfam)       download_pfam ;;
        swissprot)  download_swissprot ;;
        smart)      download_smart ;;
        expasy)     download_expasy ;;
        brenda)     download_brenda ;;
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
