# BioM3 shared data

This directory contains shared model weights and datasets for BioM3 development.

## About

The `models` directory contains weights of trained BioM3 model instances, and contains subdirectories for each component of BioM3.

The `datasets` directory contains assorted data on which one can train BioM3 components.

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

## Downloading Databases

The `download` directory contains scripts for downloading bioinformatics reference databases (NR, Pfam, SwissProt, SMART, ExPASy Enzyme, BRENDA) with retry logic, MD5 verification, and provenance logging. See [download/README.md](download/README.md) for setup and usage.

## Acknowledgments

This project was built with assistance from [Claude Code](https://claude.ai/claude-code).
