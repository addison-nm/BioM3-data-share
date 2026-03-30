# 2026-03-30 — Simplify SMART download (remove auth requirement)

## Context

Running `download_databases.sh -d smart` failed silently — the log showed `--- SMART ---` and then nothing. Root cause: an empty `smart_credentials.txt` file existed in `credentials/`, so the script entered the authenticated branch, attempted a login with blank credentials, and the subsequent curl failed under `set -e`.

Investigation showed that the bulk HMM download URL (`SMART_hmms.gz`) returns 404 — SMART no longer offers that file. The domain descriptions endpoint (`descriptions.pl`) is publicly accessible with no authentication.

## Changes

### Files modified

- `download/download_databases.sh` — replaced the SMART login/cookie auth flow with a single `download_file` call to `descriptions.pl`; removed SMART from the requirements header comment; added credential validation (`grep -q` for required keys) to both SMART and BRENDA to prevent empty-file crashes
- `download/README.md` — updated SMART overview table entry (no auth, <1 MB), removed SMART credentials from Quick Start, rewrote section 4 to reflect public download, removed `smart_cookies.txt` from output tree and security notes, updated database count to seven
- `download/credentials/README.md` — removed SMART section; noted that only BRENDA requires credentials
- `.gitignore` — removed `smart_credentials.txt` entry (no longer needed)

## Key decisions

- **Public download only** — SMART's HMM bulk download is no longer available; the domain descriptions file is the only programmatically accessible resource and needs no auth.
- **Credential validation** — both SMART (now removed) and BRENDA check for required keys in the credential file, not just file existence, to avoid silent failures from empty/stub files.
