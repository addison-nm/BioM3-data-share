# Session: Sync exclusion list, nm-team-data permissions, README per-subfolder recipe

**Date:** 2026-04-08
**Pre-session state:** `git checkout a8f7c72`

## Summary

Three related housekeeping changes:

1. **Permissions audit** of the repo against the recipes documented in [README.md](../../README.md) and [sync/README.md](../../sync/README.md). Reported drift; did not auto-fix the wider tree (deferred at the user's request).
2. **Re-permissioned `data/nm-team-data/`** to `2775 ahowe:nm-team` so members of the `nm-team` group (`sophie`, `abigail`, `ahowe`) can read and write into it, with setgid so new files inherit the group.
3. **Added a sync exclusion list feature** to `biom3sync.sh`. After a design discussion about how it should interact with the planned GitHub-template flow, the feature lives in a new `config/` directory using an `.example`/gitignored-live pattern so user customizations survive `git pull` from upstream.

## Audit findings (report only — not fixed this session)

Documented in README:

- Repo root + project files: `755`/`644`, owner-only write
- `data/` (read-only profile): `2755`/`644`
- `data/` (read-write profile): `2775`/`664`

Actual state observed:

- Repo root and all top-level project dirs/files (`README.md`, `CLAUDE.md`, `sync/`, `sync/biom3sync.sh`, `docs/`, `download/`, etc.) are `775`/`664` — group-writable, drifted from documented `755`/`644`.
- `data/` and every subdirectory under it lacks the setgid bit. New files would not inherit `biom3-dev-team`.
- `data/` file modes are mixed `644`/`664`, matching neither profile.
- `data/nm-team-data/` had wrong group entirely (`ahowe:ahowe`) and no setgid bit — fixed in Part 2.

The user explicitly chose to defer the wider permissions cleanup and only fix `nm-team-data` this session.

## Changes

### `data/nm-team-data/` (filesystem only, no commit)

```bash
sudo chown -R ahowe:nm-team /data/data-share/BioM3-data-share/data/nm-team-data
sudo chmod 2775 /data/data-share/BioM3-data-share/data/nm-team-data
sudo find /data/data-share/BioM3-data-share/data/nm-team-data -type d -exec chmod 2775 {} +
sudo find /data/data-share/BioM3-data-share/data/nm-team-data -type f -exec chmod 664 {} +
```

Verified: `2775 ahowe:nm-team`. The directory was empty so the recursive form was equivalent to a single chown, but the recipe stays correct if files are added before re-running.

### New: `config/excludes.example` (tracked)

Header-and-examples template for the new excludes feature. Documents the syntax (rsync filter rules, relative to `data/` root) and includes commented-out example patterns. Shipped in git as the canonical template for fresh template-repo instantiations.

### New: `config/excludes` (gitignored)

Live file the script actually reads. Contains a single live pattern (`nm-team-data/`) plus a brief header pointing at the example. Survives `git pull` because it's not tracked.

### `.gitignore`

Added:

```
# Local config (excludes.example is the tracked template)
/config/excludes
/config/*.local
```

The `*.local` glob is forward-looking — room for future per-clone configs.

### `sync/biom3sync.sh`

- Added `SCRIPT_DIR` (resolved via `readlink -f` so it works through the `/usr/local/bin/biom3sync` symlink) and `PROJECT_ROOT` near the top of defaults.
- Added `EXCLUDES_FILE="${PROJECT_ROOT}/config/excludes"` and `EXCLUDES_EXAMPLE="${PROJECT_ROOT}/config/excludes.example"`.
- Extended the `RSYNC_EXCLUDES` array with a conditional `--exclude-from="$EXCLUDES_FILE"` append, so the existing OS-junk excludes always run and the file just stacks on top.
- Added a small `announce_excludes()` helper that prints either the verbose `using excludes: <path>` line or a one-line `hint: cp config/excludes.example config/excludes` when only the `.example` exists. Called from both `do_sync` (push/pull) and `cmd_diff`.
- No changes to `do_sync` or `cmd_diff` rsync invocations themselves — both already expanded `"${RSYNC_EXCLUDES[@]}"`, so the new excludes flow for free.

### `sync/README.md`

- New **Excludes** section between Manifest and Catalog. Documents the `cp config/excludes.example config/excludes` setup step, the `git pull` survival guarantee under the template-repo flow, and the missing-file hint behavior.
- **How it works** bullet now mentions `config/excludes` alongside the hardcoded excludes.

### `README.md`

- New **Per-subfolder overrides** subsection under Permissions, with a worked example for `data/my-team-data` using the `my-team` group placeholder. Notes the `2755`/`644` swap for read-only and explains why the setgid bit on the subfolder matters (so new files inherit the override group instead of the parent's).

## Design discussion: where should `excludes` live?

The first iteration shipped `sync/excludes` as a tracked file in `sync/`. The user pushed back on this because they're planning to turn `BioM3-data-share` into a GitHub template repo: collaborators will instantiate their own copies and want to `git pull` upstream updates without losing their local customizations.

We weighed three approaches:

1. **`.example` pattern, gitignored live file** *(chosen)*. Tracked `config/excludes.example` ships in the template; gitignored `config/excludes` is the user's actual file. `git pull` is conflict-free on customizations. Cost: manual diff/merge when the upstream `.example` gets new recommended patterns. Matches the existing `sync/config.example` → `~/.config/biom3sync/config` pattern in the same project.
2. **Tracked `excludes` directly, manual conflict resolution.** Rejected — forces users to resolve git conflicts in a config file every time we ship a default change.
3. **Tracked baseline + gitignored `.local` additions.** More flexible (always get upstream defaults plus stacked local additions), but adds script complexity (read two files, dedupe), and the additive model has weird edge cases when upstream wants to *remove* a baseline pattern. Rejected as overkill until we actually have shared baseline excludes worth shipping.

Also asked whether `sync/config.example` should move into `config/` for consistency. User said no — `config/` is exclusively for **in-repo** configs; `sync/config.example` stays where it is because it's a template for a file that lives outside the repo (`~/.config/biom3sync/config`).

## Verification

- `bash -n sync/biom3sync.sh` — clean
- `PROJECT_ROOT` resolves correctly from script's perspective; both `config/excludes` and `config/excludes.example` detected.
- Local rsync dry-run with `--exclude-from=config/excludes` suppresses `nm-team-data/`; without it, the directory shows as `cd+++++++++ nm-team-data/`.
- `git check-ignore` confirms `config/excludes` is ignored, `config/excludes.example` is not.
- `git ls-files --others --exclude-standard config/` lists only `config/excludes.example` as a candidate for `git add`.
- `data/nm-team-data` now reports `2775 ahowe:nm-team` via `stat`.

Did not run a live remote dry-run against any of the configured ALCF/Spark remotes — the change is purely additive to a well-tested rsync flag, and the local rsync test exercises the same code path.

## Lingering work / not done

- **Wider permissions cleanup** — the audit found project files at `775`/`664` and the rest of `data/` lacking setgid. The user explicitly said "Don't fix permissions yet." Re-running the README recipes against the rest of the tree is a follow-up.
- **GitHub template repo conversion** — the design here was made *for* the template flow, but the actual conversion (template settings, README updates for downstream users, possible bootstrap script) is future work.
- **Shellcheck** — not installed on this machine; only `bash -n` syntax checking was run on the script changes.
