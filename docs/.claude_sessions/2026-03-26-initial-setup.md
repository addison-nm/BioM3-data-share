# 2026-03-26 — Initial project setup

## Git setup

- Initialized git repo tracking project structure and tooling only.
- `data/`, `.logs/`, and `.DS_Store` are gitignored.
- Pushed to private GitHub repo: `natural-machine/BioM3-data-share`.
- File permissions are tracked by git (`core.fileMode true`). On remotes, fix permissions to match rather than disabling fileMode.

## Permissions

Added a Permissions section to the top-level README covering:
- Owner-only write access for project files (`chmod -R u+rwX,go-w .`).
- Read-only `data/` for group: `chmod 2755` dirs, `chmod 644` files.
- Read-write `data/` for group: `chmod 2775` dirs, `chmod 664` files.
- Setgid bit ensures new files inherit group ownership.

## Sync tooling updates

- **Log header**: `biom3sync.sh` now writes a `#`-prefixed TSV header to `.logs/sync.log` when the file is new or empty.
- **Diff command**: Added `biom3sync diff REMOTE [SUBPATH]` to compare local vs remote data using rsync dry-run in both directions. Shows what would push and what would pull.

## Project structure additions

- `CLAUDE.md` — project context file read automatically by Claude Code.
- `docs/` — session notes directory.

## CLI installation

Symlink `biom3sync` to `/usr/local/bin` for system-wide access on macOS:

```bash
ln -s "$(pwd)/sync/biom3sync.sh" /usr/local/bin/biom3sync
```
