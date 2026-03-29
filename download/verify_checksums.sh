#!/usr/bin/env bash
# =============================================================================
# verify_checksums.sh
# Recomputes MD5 checksums for all downloaded database files and compares
# them against the provenance ledger produced during download.
#
# Usage:
#   bash verify_checksums.sh [-d BASE_DIR]
# =============================================================================

set -euo pipefail

BASE_DIR="${1:-./databases}"
PROVENANCE="$BASE_DIR/provenance.tsv"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
REPORT="$BASE_DIR/logs/verify_${TIMESTAMP//:/}.log"

mkdir -p "$BASE_DIR/logs"

log() { echo "[$( date -u +"%Y-%m-%dT%H:%M:%SZ")] $*" | tee -a "$REPORT"; }

md5_of() {
    if command -v md5sum &>/dev/null; then
        md5sum "$1" | awk '{print $1}'
    else
        md5 -q "$1"
    fi
}

if [[ ! -f "$PROVENANCE" ]]; then
    echo "Provenance file not found: $PROVENANCE" >&2
    exit 1
fi

log "Verification run: $TIMESTAMP"
log "Provenance file : $PROVENANCE"
log "Base dir        : $BASE_DIR"
log "-----------------------------------------------------------------------"

PASS=0; FAIL=0; SKIP=0

# Skip header line
tail -n +2 "$PROVENANCE" | while IFS=$'\t' read -r dl_ts filename source_url recorded_md5; do
    # Try to locate the file
    found=$(find "$BASE_DIR" -name "$filename" 2>/dev/null | head -1)

    if [[ -z "$found" ]]; then
        log "SKIP  $filename  (file not found on disk)"
        (( SKIP++ )) || true
        continue
    fi

    if [[ "$recorded_md5" == "manual-login-required" || \
          "$recorded_md5" == "credentials-required"  || \
          "$recorded_md5" == "md5-tool-not-found"    ]]; then
        log "SKIP  $filename  (recorded MD5 is placeholder: $recorded_md5)"
        (( SKIP++ )) || true
        continue
    fi

    actual_md5=$(md5_of "$found")

    if [[ "$actual_md5" == "$recorded_md5" ]]; then
        log "PASS  $filename  $actual_md5"
        (( PASS++ )) || true
    else
        log "FAIL  $filename  expected=$recorded_md5  actual=$actual_md5"
        (( FAIL++ )) || true
    fi
done

log "-----------------------------------------------------------------------"
log "Results: PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP"
log "Report saved to: $REPORT"

if (( FAIL > 0 )); then
    echo "VERIFICATION FAILED: $FAIL file(s) have mismatched checksums." >&2
    exit 1
fi
