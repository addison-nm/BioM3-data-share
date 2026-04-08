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

### Data directory (read-only for group)

To allow group members to read but not modify anything under `data/`:

```bash
sudo chown -R <owner>:<group> data/
sudo chmod 2755 data/
sudo find data/ -type d -exec chmod 2755 {} +
sudo find data/ -type f -exec chmod 644 {} +
```

The setgid bit (`2`) ensures new files and subdirectories inherit the group. Group and others get read-only access.

### Data directory (read-write for group)

To allow group members to both read and write under `data/`:

```bash
sudo chown -R <owner>:<group> data/
sudo chmod 2775 data/
sudo find data/ -type d -exec chmod 2775 {} +
sudo find data/ -type f -exec chmod 664 {} +
```

Here group members can create, modify, and delete files. The setgid bit ensures new entries inherit the group ownership.

### Per-subfolder overrides

To grant a different group access to a single subfolder under `data/` (e.g. give `my-team` read-write access to `data/my-team-data/` while the rest of `data/` stays owned by the project group), apply the same recipe scoped to that subfolder:

```bash
sudo chown -R <owner>:my-team data/my-team-data
sudo chmod 2775 data/my-team-data
sudo find data/my-team-data -type d -exec chmod 2775 {} +
sudo find data/my-team-data -type f -exec chmod 664 {} +
```

Use `2755`/`644` instead of `2775`/`664` for read-only group access. The setgid bit on the subfolder is what makes new files inherit the override group instead of the parent's group.

## Downloading Databases

The `download` directory contains scripts for downloading bioinformatics reference databases (NR, Pfam, SwissProt, SMART, ExPASy Enzyme, BRENDA) with retry logic, MD5 verification, and provenance logging. See [download/README.md](download/README.md) for setup and usage.

## Acknowledgments

This project was built with assistance from [Claude Code](https://claude.ai/claude-code).
