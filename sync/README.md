# BioM3 Sync

`biom3sync.sh` pushes and pulls the `BioM3-data-share` directory to and from remote compute clusters.

## Remotes

| Name | Host | Auth |
| ------ | ------ | ------ |
| `aurora` | `aurora.alcf.anl.gov` | 2FA (MobilePass+) |
| `polaris` | `polaris.alcf.anl.gov` | 2FA (MobilePass+) |
| `spark` | `spark-nm` (Tailscale alias) | SSH key |

Remote data lives at `<remote_PATH>/data/` on each machine (the script appends `/data` automatically; set `remote_PATH` to the project root, e.g. `/lus/flare/projects/<project>/BioM3-data-share`).

## Setup

**1. Install the config** (one time per machine):

```bash
mkdir -p ~/.config/biom3sync
cp sync/config.example ~/.config/biom3sync/config
$EDITOR ~/.config/biom3sync/config
```

Fill in `YOUR_ALCF_USERNAME`, `YOUR_PROJECT`, `YOUR_SPARK_USERNAME`, and the Spark remote path. The config is machine-local and should not be committed anywhere.

**2. (Optional) Put the script on your PATH:**

```bash
ln -s "$(pwd)/sync/biom3sync.sh" /usr/local/bin/biom3sync
```

## Usage

```text
biom3sync [OPTIONS] COMMAND [ARGS]

Commands:
  connect    REMOTE                   open SSH master session (required for 2FA remotes)
  disconnect REMOTE                   close SSH master session
  status                              show connection status for all remotes
  push       [REMOTE|all] [SUBPATH]   push data to remote(s)
  pull       [REMOTE|all] [SUBPATH]   pull data from remote(s)
  diff       REMOTE [SUBPATH]        compare local and remote data
  manifest   [-d DEPTH] [--no-checksum]   generate manifest.json + manifest.txt
  catalog                             add stub entries to CATALOG.md for new directories

Options:
  -n, --dry-run    show what would transfer without transferring
  -v, --verbose    verbose output
```

## Workflow

ALCF machines require 2FA. Establish a master SSH session first — it stays open for 4 hours, so you only authenticate once per working session regardless of how many push/pull operations you run.

```bash
# Authenticate (2FA prompt appears here, once)
biom3sync connect aurora
biom3sync connect polaris

# Check session status
biom3sync status

# Push/pull — no re-authentication needed while session is open
biom3sync push aurora                  # push everything to aurora
biom3sync push aurora datasets/CM      # push one subdirectory
biom3sync pull spark weights/LLMs      # pull from spark (no connect needed)
biom3sync -n push all                  # dry-run to all three remotes

# Close sessions when done
biom3sync disconnect aurora
biom3sync disconnect polaris
```

Spark uses SSH key authentication via the `spark-nm` alias in `~/.ssh/config`, so no `connect` step is needed.

## Manifest

`biom3sync manifest` scans the local data root and writes two files:

- **`manifest.txt`** — human-readable directory tree with file sizes and checksums
- **`manifest.json`** — flat list of all entries, suitable for programmatic diffing

```bash
biom3sync manifest                     # full scan, depth 3, with md5 checksums
biom3sync manifest -d 2                # scan to depth 2 only
biom3sync manifest --no-checksum       # skip md5 (much faster for large files)
biom3sync manifest -d 2 --no-checksum  # fast tree overview
```

Checksums are computed by default. For the largest files (e.g. 37 GB Pfam), this takes several minutes — use `--no-checksum` when you just want a structural overview.

`manifest.json` and `manifest.txt` are synced to remotes via push/pull, so collaborators can inspect what's available without downloading everything.

## Excludes

`config/excludes` is an optional file that lists paths under `data/` to skip
during push, pull, and diff. Patterns use rsync filter syntax and are
interpreted relative to the `data/` root.

The repo ships `config/excludes.example` as a template. Create your live
file with:

```bash
cp config/excludes.example config/excludes
$EDITOR config/excludes
```

`config/excludes` is gitignored, so your customizations survive `git pull`
when this project is used as a GitHub template — upstream may update
`config/excludes.example`, but your live file is never touched. To pick up
new recommended patterns from upstream, diff the example against your local
copy and merge by hand.

```text
# Example config/excludes
nm-team-data/          # skip an entire subdirectory
*.tmp.npy              # glob anywhere under data/
/scratch/              # anchored to data/ root
```

Run with `-v` to confirm the file is being honored — `biom3sync` prints
`using excludes: <path>` before each rsync invocation in verbose mode. If
`config/excludes` is missing but `config/excludes.example` exists, you'll
get a one-line hint about the copy step. With no excludes file at all, sync
proceeds with only the built-in excludes (OS junk and `.logs/`).

## Catalog

`CATALOG.md` is a human-maintained documentation file describing the contents of the data share. Run `biom3sync catalog` to automatically add stub entries for any directories not yet documented:

```bash
biom3sync catalog
```

This will:

- Create `CATALOG.md` with a header if it doesn't exist
- Update the _Last updated_ date
- Append a stub section for each directory (up to depth 2) not already mentioned — **existing content is never modified or removed**

Fill in the stubs by hand and commit the updated `CATALOG.md` to OneDrive.

## Sync log

Every push and pull is recorded in `.logs/sync.log` (tab-separated):

```text
timestamp  status  direction  remote  subpath  user  hostname  dry_run  duration_s
```

The `.logs/` directory is excluded from rsync so it is never overwritten on remotes. OneDrive automatically syncs it across collaborators' machines, giving a shared history of who pushed what and when.

## How it works

- **rsync over SSH** with `-azhP`: archive mode, compression, human-readable output, and partial-file resumption (safe for large interrupted transfers).
- **SSH ControlMaster** (`-fNM -o ControlPersist=4h`): opens a background SSH session that subsequent connections multiplex through. This is what allows 2FA to be entered only once.
- **Excludes from rsync**: hardcoded — `.DS_Store`, `._*`, `.Spotlight-V100`, `.Trashes`, `*.tmp`, `*.swp`, `.~lock.*`, `.logs/`. Plus any patterns in `config/excludes` (see [Excludes](#excludes)).
- ControlMaster sockets are stored in `~/.config/biom3sync/sockets/` (permissions 700, not synced to OneDrive).

## Adding a new remote

1. Add the name to the `REMOTES=(...)` list in your config.
2. Add the corresponding `name_HOST`, `name_USER`, `name_PATH`, and `name_AUTH` variables.
3. Set `name_AUTH` to `key` (SSH key) or `2fa` (requires `connect` before syncing).
