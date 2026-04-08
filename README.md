# BioM3 shared data

This directory contains shared model weights and datasets for BioM3 development.

## About

BioM3-data-share is part of a multi-repo ecosystem:

| Repository | Role | Description |
|------------|------|-------------|
| [BioM3-dev](https://github.com/addison-nm/BioM3-dev) | Core library | Python package: 3-stage pipeline, dataset construction, training |
| **BioM3-data-share** (this repo) | Shared data | Model weights, datasets, and reference databases synced across clusters |
| [BioM3-workflow-demo](https://github.com/natural-machine/BioM3-workflow-demo) | Demo workflows | End-to-end finetuning and generation demonstration pipeline |
| BioM3-workspace-template | Workspace setup | *(Planned)* Standardized workspace template for new research projects |

See [docs/biom3_ecosystem.md](./docs/biom3_ecosystem.md) for cross-repo workflows, version compatibility, and shared data architecture.

The `data/weights/` directory contains weights of trained BioM3 model instances, with subdirectories for each component of BioM3.

The `data/datasets/` directory contains assorted data on which one can train BioM3 components.

The `databases/` directory contains downloaded bioinformatics reference databases (NR, Pfam, SwissProt, etc.). These are downloaded per-machine and are not synced across clusters.

For questions, contact Addison at <addison@thenaturalmachine.ai>.

## Syncing

The `sync` directory contains a script and config for pushing and pulling data to remote compute clusters (ALCF Aurora, ALCF Polaris, DGX Spark). See [sync/README.md](sync/README.md) for setup and usage.

## Permissions

After cloning on a shared machine, set ownership and permissions so that only the owner can modify project files while group members can read.

### Project files

Restrict the repo root and directories like `sync/` so only the owner has write and execute access:

```bash
sudo chown -R <owner>:<group> .
chmod 755 .
chmod -R u+rwX,go-w .
```

This gives the owner full access and everyone else read/execute on directories and read on files. Scripts like `sync/biom3sync.sh` retain their executable bit.

### `data/` — group read-only base

The canonical profile for `data/`: the project group (e.g. `biom3-dev-team`) can read everything; only the owner can write. New files added by the owner inherit the project group automatically thanks to the setgid bit.

```bash
sudo chown -R <owner>:<project-group> data
sudo chmod 2755 data
sudo find data -type d -exec chmod 2755 {} +
sudo find data -type f -exec chmod 644 {} +
```

The setgid bit (`2`) on directories ensures new entries inherit the project group instead of the creator's primary group. Group and others get read + traverse, no write.

A read-write base variant (Profile B) is documented in [docs/permissions.md](docs/permissions.md) for cases where group members need to write directly to `data/`. It requires a default ACL to survive umask masking — see the runbook for the full recipe.

### Per-subfolder lockdown override

To carve out a subfolder under `data/` that only one specific group can access (read or write), apply this recipe *after* the base profile. Example: give `<team>` exclusive access to `data/<team>-data/` while the rest of `data/` stays project-group readable.

```bash
sudo chown -R :<team> data/<team>-data
sudo chmod 3770 data/<team>-data
sudo find data/<team>-data -mindepth 1 -type d -exec chmod 2770 {} +
sudo find data/<team>-data -type f -exec chmod 660 {} +
sudo setfacl -k data/<team>-data
sudo setfacl -d -m u::rwx,g::rwx,o::--- data/<team>-data
```

The `chown -R :<team>` only changes the group, preserving whoever created each file. Mode `3770` on the top of the override sets setgid (`2`) so new entries inherit `<team>`, sticky (`1`) so only a file's owner can delete or rename top-level entries, and `770` so non-`<team>` users have no access at all — they can't even `ls` the directory. Nested directories get `2770` (setgid only; sticky doesn't propagate via `mkdir`). The default ACL forces new files to land at `660` and new directories at `2770` regardless of each contributor's umask, which is otherwise the silent failure mode of group-writable directories. See [docs/permissions.md](docs/permissions.md) for the full reapply procedure with verification, limitations, and a read-write base variant.

## Downloading Databases

The `download` directory contains scripts for downloading bioinformatics reference databases (NR, Pfam, SwissProt, SMART, ExPASy Enzyme, BRENDA) with retry logic, MD5 verification, and provenance logging. See [download/README.md](download/README.md) for setup and usage.

## Acknowledgments

This project was built with assistance from [Claude Code](https://claude.ai/claude-code).
