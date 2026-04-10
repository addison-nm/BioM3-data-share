#!/usr/bin/env bash
# biom3sync.sh — BioM3 data sync utility
#
# USAGE
#   biom3sync [OPTIONS] COMMAND [ARGS]
#
# COMMANDS
#   connect    REMOTE                   open SSH master session (required for 2FA remotes)
#   disconnect REMOTE                   close SSH master session
#   status                              show connection status for all remotes
#   push       [REMOTE|all] [SUBPATH]   push data to remote(s)
#   pull       [REMOTE|all] [SUBPATH]   pull data from remote(s)
#   manifest   [-d DEPTH] [--no-checksum]   generate manifest.json + manifest.txt
#   catalog                             add stub entries to CATALOG.md for new directories
#   diff       REMOTE [SUBPATH]         compare local and remote data
#
# OPTIONS (place before command)
#   -n, --dry-run    show what would transfer without transferring
#   -v, --verbose    verbose output
#
# REMOTES
#   aurora, polaris   ALCF clusters (2FA — run 'connect' first, valid 4h)
#   spark             DGX Spark (SSH key via Tailscale, no connect needed)
#
# SUBPATH  Optional path relative to BioM3-data-share root.
#   e.g.   datasets/CM    weights/LLMs
#
# EXAMPLES
#   biom3sync connect aurora                  # authenticate once (2FA prompt)
#   biom3sync push aurora                     # push everything to aurora
#   biom3sync push aurora datasets/CM         # push only datasets/CM to aurora
#   biom3sync -n push all                     # dry-run push to all remotes
#   biom3sync pull spark weights               # pull weights/ from spark
#   biom3sync disconnect aurora
#   biom3sync diff spark                       # compare local vs spark
#   biom3sync diff aurora datasets/CM          # compare a subdirectory
#   biom3sync manifest                        # generate manifest with checksums
#   biom3sync manifest -d 2 --no-checksum     # fast tree-only manifest, depth 2
#   biom3sync catalog                         # add stubs for any undocumented directories
#
# CONFIG
#   Copy sync/config.example to ~/.config/biom3sync/config and fill in values.
#
# LOGS
#   Push/pull operations are logged to .logs/sync.log in the data root.
#   This directory is excluded from rsync; OneDrive syncs it across machines.

set -euo pipefail

# ── defaults ──────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
EXCLUDES_FILE="${PROJECT_ROOT}/config/excludes"
EXCLUDES_EXAMPLE="${PROJECT_ROOT}/config/excludes.example"
CONFIG_FILE="${HOME}/.config/biom3sync/config"
CONTROL_DIR="${HOME}/.config/biom3sync/sockets"
CONTROL_PERSIST="4h"
DRY_RUN=false
VERBOSE=false

RSYNC_EXCLUDES=(
    --exclude='.DS_Store'
    --exclude='._*'
    --exclude='.Spotlight-V100'
    --exclude='.Trashes'
    --exclude='*.tmp'
    --exclude='*.swp'
    --exclude='.~lock.*'
    --exclude='.logs/'
)
if [[ -f "$EXCLUDES_FILE" ]]; then
    RSYNC_EXCLUDES+=( --exclude-from="$EXCLUDES_FILE" )
fi

# ── parse flags ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run) DRY_RUN=true;  shift ;;
        -v|--verbose) VERBOSE=true;  shift ;;
        --) shift; break ;;
        -*) echo "Unknown option: $1" >&2; exit 1 ;;
        *)  break ;;
    esac
done

# ── load config ───────────────────────────────────────────────────────────────
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: config not found at $CONFIG_FILE" >&2
    echo "" >&2
    echo "Set it up with:" >&2
    echo "  mkdir -p ~/.config/biom3sync" >&2
    echo "  cp \"$(dirname "$0")/config.example\" ~/.config/biom3sync/config" >&2
    echo "  \$EDITOR ~/.config/biom3sync/config" >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$CONFIG_FILE"

# Data lives in a subdirectory of the project root so that tooling (sync/,
# .logs/, README.md) is cleanly separated from synced content.
DATA_ROOT="${LOCAL_ROOT%/}/data"

# ── helpers ───────────────────────────────────────────────────────────────────

# Get a per-remote config variable: remote_var aurora HOST → $aurora_HOST
remote_var() {
    local remote="$1" key="$2"
    eval "echo \"\${${remote}_${key}}\""
}

socket_path() { echo "${CONTROL_DIR}/$1.sock"; }

is_connected() {
    local remote="$1"
    local host user sock
    host=$(remote_var "$remote" HOST)
    user=$(remote_var "$remote" USER)
    sock=$(socket_path "$remote")
    [[ -S "$sock" ]] && ssh -O check -S "$sock" "${user}@${host}" 2>/dev/null
}

require_connection() {
    local remote="$1"
    local auth
    auth=$(remote_var "$remote" AUTH)
    if [[ "$auth" == "2fa" ]] && ! is_connected "$remote"; then
        echo "Error: not connected to $remote." >&2
        echo "  Run: $(basename "$0") connect $remote" >&2
        exit 1
    fi
}

# Build the -e 'ssh ...' string for rsync, injecting ControlPath when available
ssh_e_flag() {
    local remote="$1"
    local sock
    sock=$(socket_path "$remote")
    if [[ -S "$sock" ]]; then
        echo "ssh -o ControlPath=${sock} -o BatchMode=yes"
    else
        echo "ssh"
    fi
}

rsync_base_flags() {
    # -a  archive (recursive, preserve perms/times/links)
    # -z  compress in transit
    # -P  show progress + keep partial files (safe for large transfers)
    # -h  human-readable sizes
    local flags=(-azhP)
    $DRY_RUN  && flags+=(--dry-run)
    $VERBOSE  && flags+=(-v)
    echo "${flags[@]}"
}

validate_remote() {
    local remote="$1"
    if [[ ! " ${REMOTES[*]} " =~ " ${remote} " ]]; then
        echo "Unknown remote: '$remote'" >&2
        echo "Available remotes: ${REMOTES[*]}" >&2
        exit 1
    fi
}

# Print info about config/excludes before each sync. If the live file is
# missing but the example exists, hint at the copy step (so users coming
# from a fresh template instantiation know how to enable custom excludes).
announce_excludes() {
    if [[ -f "$EXCLUDES_FILE" ]]; then
        if $VERBOSE; then
            echo "  using excludes: $EXCLUDES_FILE"
        fi
    elif [[ -f "$EXCLUDES_EXAMPLE" ]]; then
        echo "  hint: cp config/excludes.example config/excludes  to enable custom excludes"
    fi
    # Explicit return 0 so set -e doesn't kill the script if the last echo is skipped.
    return 0
}

# Append one TSV record to .logs/sync.log
# log_entry STATUS DIRECTION REMOTE SUBPATH DRY_RUN [DURATION_S]
log_entry() {
    local status="$1" direction="$2" remote="$3" subpath="$4" dry_run="$5"
    local duration="${6:-}"
    local log_file="${LOCAL_ROOT%/}/.logs/sync.log"
    local timestamp hostname
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    hostname=$(hostname -s 2>/dev/null || echo "unknown")
    mkdir -p "$(dirname "$log_file")"
    # Write header if the log file is new or empty
    if [[ ! -s "$log_file" ]]; then
        printf "#%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "timestamp" "status" "direction" "remote" \
            "subpath" "user" "hostname" "dry_run" "duration_s" \
            >> "$log_file"
    fi
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$timestamp" "$status" "$direction" "$remote" \
        "${subpath:-.}" "${USER:-unknown}" "$hostname" \
        "$dry_run" "$duration" \
        >> "$log_file"
}

# Cross-platform md5 checksum
md5_file() {
    if command -v md5sum &>/dev/null; then
        md5sum "$1" | awk '{print $1}'
    else
        md5 -q "$1"
    fi
}

# Cross-platform file size in bytes
file_size_bytes() {
    if [[ "$(uname)" == "Darwin" ]]; then
        stat -f%z "$1" 2>/dev/null || echo 0
    else
        stat -c%s "$1" 2>/dev/null || echo 0
    fi
}

# ── commands ──────────────────────────────────────────────────────────────────

cmd_connect() {
    local remote="${1:-}"
    [[ -z "$remote" ]] && { echo "Usage: $(basename "$0") connect REMOTE"; exit 1; }
    validate_remote "$remote"

    local host user sock auth
    host=$(remote_var "$remote" HOST)
    user=$(remote_var "$remote" USER)
    sock=$(socket_path "$remote")
    auth=$(remote_var "$remote" AUTH)

    if is_connected "$remote"; then
        echo "$remote: already connected (${user}@${host})"
        return 0
    fi

    mkdir -p "$CONTROL_DIR"
    chmod 700 "$CONTROL_DIR"

    echo "Connecting to $remote (${user}@${host})..."
    [[ "$auth" == "2fa" ]] && echo "You will be prompted for 2FA authentication."

    ssh -fNM \
        -S "$sock" \
        -o ControlPersist="$CONTROL_PERSIST" \
        -o ServerAliveInterval=60 \
        -o ServerAliveCountMax=5 \
        "${user}@${host}"

    echo "Connected. Session persists for ${CONTROL_PERSIST}."
}

cmd_disconnect() {
    local remote="${1:-}"
    [[ -z "$remote" ]] && { echo "Usage: $(basename "$0") disconnect REMOTE"; exit 1; }
    validate_remote "$remote"

    local host user sock
    host=$(remote_var "$remote" HOST)
    user=$(remote_var "$remote" USER)
    sock=$(socket_path "$remote")

    if ! is_connected "$remote"; then
        echo "$remote: not connected"
        return 0
    fi

    ssh -O exit -S "$sock" "${user}@${host}" 2>/dev/null
    echo "Disconnected from $remote."
}

cmd_status() {
    echo "Remote connections:"
    for remote in "${REMOTES[@]}"; do
        local host user auth
        host=$(remote_var "$remote" HOST)
        user=$(remote_var "$remote" USER)
        auth=$(remote_var "$remote" AUTH)
        if is_connected "$remote"; then
            printf "  %-10s [connected]    %s@%s\n" "$remote" "$user" "$host"
        else
            local auth_note
            [[ "$auth" == "2fa" ]] && auth_note=" (run: connect $remote)" || auth_note=""
            printf "  %-10s [disconnected]%s\n" "$remote" "$auth_note"
        fi
    done
}

do_sync() {
    local direction="$1"   # push | pull
    local remote="$2"
    local subpath="${3:-}"

    validate_remote "$remote"
    require_connection "$remote"

    local host user rpath
    host=$(remote_var "$remote" HOST)
    user=$(remote_var "$remote" USER)
    rpath=$(remote_var "$remote" PATH)

    # Normalise subpath: strip leading/trailing slashes
    subpath="${subpath#/}"
    subpath="${subpath%/}"

    local local_base="${DATA_ROOT%/}"
    local remote_base="${rpath%/}/data"

    local local_path remote_path
    if [[ -n "$subpath" ]]; then
        local_path="${local_base}/${subpath}"
        remote_path="${remote_base}/${subpath}"
    else
        local_path="${local_base}"
        remote_path="${remote_base}"
    fi

    # Trailing slash on source tells rsync to copy contents, not the dir itself
    local src dst
    if [[ "$direction" == "push" ]]; then
        src="${local_path}/"
        dst="${user}@${host}:${remote_path}/"
        echo "→ push  $remote  ${subpath:-.}/"
    else
        src="${user}@${host}:${remote_path}/"
        dst="${local_path}/"
        echo "← pull  $remote  ${subpath:-.}/"
    fi

    if $DRY_RUN; then
        echo "  [dry run — no files will be transferred]"
    fi
    announce_excludes

    local ssh_e
    ssh_e=$(ssh_e_flag "$remote")

    local start_time
    start_time=$(date +%s)
    log_entry "STARTED" "$direction" "$remote" "$subpath" "$DRY_RUN"

    local exit_code=0
    # shellcheck disable=SC2046
    rsync $(rsync_base_flags) "${RSYNC_EXCLUDES[@]}" \
        -e "$ssh_e" \
        "$src" "$dst" || exit_code=$?

    local duration=$(( $(date +%s) - start_time ))
    if [[ $exit_code -eq 0 ]]; then
        log_entry "SUCCESS" "$direction" "$remote" "$subpath" "$DRY_RUN" "$duration"
        echo "Done.  (${duration}s)"
    else
        log_entry "FAILED"  "$direction" "$remote" "$subpath" "$DRY_RUN" "$duration"
        echo "rsync exited with code ${exit_code}." >&2
        return "$exit_code"
    fi
}

cmd_push() {
    local target="${1:-all}"
    local subpath="${2:-}"

    if [[ "$target" == "all" ]]; then
        for remote in "${REMOTES[@]}"; do
            do_sync push "$remote" "$subpath"
        done
    else
        do_sync push "$target" "$subpath"
    fi
}

cmd_pull() {
    local target="${1:-all}"
    local subpath="${2:-}"

    if [[ "$target" == "all" ]]; then
        for remote in "${REMOTES[@]}"; do
            do_sync pull "$remote" "$subpath"
        done
    else
        do_sync pull "$target" "$subpath"
    fi
}

# ── diff ──────────────────────────────────────────────────────────────────────

cmd_diff() {
    local remote="${1:-}"
    local subpath="${2:-}"
    [[ -z "$remote" ]] && { echo "Usage: $(basename "$0") diff REMOTE [SUBPATH]"; exit 1; }

    validate_remote "$remote"
    require_connection "$remote"

    local host user rpath
    host=$(remote_var "$remote" HOST)
    user=$(remote_var "$remote" USER)
    rpath=$(remote_var "$remote" PATH)

    subpath="${subpath#/}"
    subpath="${subpath%/}"

    local local_base="${DATA_ROOT%/}"
    local remote_base="${rpath%/}/data"

    local local_path remote_path
    if [[ -n "$subpath" ]]; then
        local_path="${local_base}/${subpath}"
        remote_path="${remote_base}/${subpath}"
    else
        local_path="${local_base}"
        remote_path="${remote_base}"
    fi

    local ssh_e
    ssh_e=$(ssh_e_flag "$remote")

    local rsync_flags=(-azn --itemize-changes)
    $VERBOSE && rsync_flags+=(-v)

    echo "Comparing local ↔ ${remote}  ${subpath:-.}/"
    announce_excludes
    echo ""

    # Local → remote: files that would be pushed
    echo "── Local only / newer locally (would push) ──"
    local push_out
    push_out=$(rsync "${rsync_flags[@]}" "${RSYNC_EXCLUDES[@]}" \
        -e "$ssh_e" \
        "${local_path}/" "${user}@${host}:${remote_path}/" 2>/dev/null) || true

    if [[ -z "$push_out" ]]; then
        echo "  (in sync)"
    else
        echo "$push_out" | while IFS= read -r line; do
            echo "  $line"
        done
    fi

    echo ""

    # Remote → local: files that would be pulled
    echo "── Remote only / newer on ${remote} (would pull) ──"
    local pull_out
    pull_out=$(rsync "${rsync_flags[@]}" "${RSYNC_EXCLUDES[@]}" \
        -e "$ssh_e" \
        "${user}@${host}:${remote_path}/" "${local_path}/" 2>/dev/null) || true

    if [[ -z "$pull_out" ]]; then
        echo "  (in sync)"
    else
        echo "$pull_out" | while IFS= read -r line; do
            echo "  $line"
        done
    fi
}

# ── manifest ──────────────────────────────────────────────────────────────────

# Names to skip when walking the data tree
_MANIFEST_SKIP=('.DS_Store' '._*' '.Spotlight-V100' '.Trashes' '.git')

_manifest_skip_name() {
    local name="$1"
    for pat in "${_MANIFEST_SKIP[@]}"; do
        # shellcheck disable=SC2254
        case "$name" in $pat) return 0 ;; esac
    done
    return 1
}

# Recursive tree walker.
# Globals written: _JSON_ENTRIES (array), _TXT_LINES (array)
# DO_CHECKSUM must be set before calling.
_manifest_walk() {
    local dir="$1"
    local depth="$2"
    local prefix="$3"    # tree-drawing prefix for txt
    local rel_base="$4"  # relative path from LOCAL_ROOT

    [[ $depth -le 0 ]] && return

    # Collect children, sorted
    local children=()
    while IFS= read -r child; do
        [[ -z "$child" ]] && continue
        _manifest_skip_name "$(basename "$child")" && continue
        children+=("$child")
    done < <(find "$dir" -maxdepth 1 -mindepth 1 | sort)

    local total=${#children[@]}
    local idx=0

    for child in "${children[@]}"; do
        idx=$(( idx + 1 ))
        local name
        name=$(basename "$child")
        local rel_path="${rel_base:+${rel_base}/}${name}"

        local connector child_prefix
        if [[ $idx -eq $total ]]; then
            connector="└── "
            child_prefix="${prefix}    "
        else
            connector="├── "
            child_prefix="${prefix}│   "
        fi

        if [[ -d "$child" ]]; then
            local size_human
            size_human=$(du -sh "$child" 2>/dev/null | awk '{print $1}')
            _TXT_LINES+=("${prefix}${connector}${name}/  [${size_human}]")
            _JSON_ENTRIES+=("{\"path\": \"${rel_path}\", \"type\": \"dir\", \"size_human\": \"${size_human}\"}")
            _manifest_walk "$child" $(( depth - 1 )) "$child_prefix" "$rel_path"
        else
            local size_bytes size_human
            size_bytes=$(file_size_bytes "$child")
            size_human=$(du -sh "$child" 2>/dev/null | awk '{print $1}')

            local md5_display="" md5_val=""
            if $DO_CHECKSUM; then
                echo -n "  checksumming ${rel_path} ... " >&2
                md5_val=$(md5_file "$child")
                echo "done" >&2
                md5_display="  md5:${md5_val}"
            fi

            _TXT_LINES+=("${prefix}${connector}${name}  [${size_human}]${md5_display}")

            local json_entry
            json_entry="{\"path\": \"${rel_path}\", \"type\": \"file\", \"size_bytes\": ${size_bytes}, \"size_human\": \"${size_human}\""
            $DO_CHECKSUM && json_entry+=", \"md5\": \"${md5_val}\""
            json_entry+="}"
            _JSON_ENTRIES+=("$json_entry")
        fi
    done
}

cmd_manifest() {
    local depth=3
    DO_CHECKSUM=true   # global, read by _manifest_walk

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--depth)      depth="$2"; shift 2 ;;
            --no-checksum)   DO_CHECKSUM=false; shift ;;
            *) echo "Unknown manifest option: $1" >&2; exit 1 ;;
        esac
    done

    local out_json="${DATA_ROOT}/manifest.json"
    local out_txt="${DATA_ROOT}/manifest.txt"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local root_name
    root_name=$(basename "${DATA_ROOT%/}")

    echo "Generating manifest (depth=${depth}, checksums=${DO_CHECKSUM})..."

    _JSON_ENTRIES=()
    _TXT_LINES=()
    _manifest_walk "${DATA_ROOT%/}" "$depth" "" ""

    # ── Write manifest.txt ────────────────────────────────────────────────────
    {
        echo "${root_name}/  (generated ${timestamp}, depth=${depth}, checksums=${DO_CHECKSUM})"
        for line in "${_TXT_LINES[@]}"; do
            echo "$line"
        done
    } > "$out_txt"

    # ── Write manifest.json ───────────────────────────────────────────────────
    {
        echo "{"
        echo "  \"generated\": \"${timestamp}\","
        echo "  \"depth\": ${depth},"
        echo "  \"checksums\": ${DO_CHECKSUM},"
        echo "  \"entries\": ["
        local n=${#_JSON_ENTRIES[@]}
        local i=0
        for entry in "${_JSON_ENTRIES[@]}"; do
            i=$(( i + 1 ))
            if [[ $i -lt $n ]]; then
                echo "    ${entry},"
            else
                echo "    ${entry}"
            fi
        done
        echo "  ]"
        echo "}"
    } > "$out_json"

    echo "Written: manifest.txt  manifest.json"
}

# ── catalog ───────────────────────────────────────────────────────────────────

cmd_catalog() {
    local catalog="${DATA_ROOT}/CATALOG.md"
    local scan_depth=2
    local today
    today=$(date +%Y-%m-%d)

    # Directories to skip
    local skip_dirs=('.git' 'test_dir')

    # Collect directories up to scan_depth, relative to LOCAL_ROOT
    local dirs=()
    while IFS= read -r d; do
        [[ -z "$d" ]] && continue
        local rel="${d#${DATA_ROOT%/}/}"
        local top="${rel%%/*}"
        local skip=false
        for s in "${skip_dirs[@]}"; do [[ "$top" == "$s" ]] && skip=true && break; done
        $skip && continue
        dirs+=("$rel")
    done < <(find "${DATA_ROOT%/}" -mindepth 1 -maxdepth "$scan_depth" -type d | sort)

    # Create file with header if it doesn't exist
    if [[ ! -f "$catalog" ]]; then
        cat > "$catalog" <<EOF
# BioM3 Data Catalog

_Last updated: ${today}_

Document the contents of this data share here. Run \`biom3sync catalog\` to add
stub entries for any directories not yet listed.

EOF
        echo "Created CATALOG.md"
    else
        # Update the _Last updated_ line
        if grep -q '_Last updated:' "$catalog"; then
            # Use sed for in-place edit, cross-platform
            sed -i.bak "s|_Last updated:.*_|_Last updated: ${today}_|" "$catalog" \
                && rm -f "${catalog}.bak"
        fi
    fi

    local existing
    existing=$(cat "$catalog")
    local added=0

    for rel in "${dirs[@]}"; do
        # Check if this path is already mentioned in the catalog
        if echo "$existing" | grep -qF "$rel"; then
            continue
        fi

        cat >> "$catalog" <<EOF

## ${rel}/

**Description**: <!-- TODO -->
**Source**: <!-- TODO -->
**Date added**: <!-- TODO -->
**Notes**: <!-- TODO -->

EOF
        echo "  Added stub: ${rel}/"
        added=$(( added + 1 ))
        # Keep existing up to date so we don't add duplicates in the same run
        existing=$(cat "$catalog")
    done

    if [[ $added -eq 0 ]]; then
        echo "CATALOG.md is up to date — no new directories found."
    else
        echo "Added ${added} stub(s) to CATALOG.md"
    fi
}

# ── usage ─────────────────────────────────────────────────────────────────────

usage() {
    sed -n '3,46p' "$0" | sed 's/^# \?//'
}

# ── dispatch ──────────────────────────────────────────────────────────────────
COMMAND="${1:-help}"
shift || true

case "$COMMAND" in
    connect)    cmd_connect    "$@" ;;
    disconnect) cmd_disconnect "$@" ;;
    status)     cmd_status ;;
    push)       cmd_push       "$@" ;;
    pull)       cmd_pull       "$@" ;;
    diff)       cmd_diff       "$@" ;;
    manifest)   cmd_manifest   "$@" ;;
    catalog)    cmd_catalog ;;
    help|--help|-h) usage ;;
    *) echo "Unknown command: $COMMAND"; echo ""; usage; exit 1 ;;
esac
