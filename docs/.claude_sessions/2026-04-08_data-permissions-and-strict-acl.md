# Session: data/ permissions cleanup, sticky bit, strict ACL variant

**Date:** 2026-04-08
**Pre-session state:** `git checkout a14be7a`

## Summary

Direct continuation of [2026-04-08_sync-excludes-and-permissions.md](2026-04-08_sync-excludes-and-permissions.md), which left a `data/` permissions audit unresolved. This session:

1. **Reapplied the documented read-only profile** to all of `data/` (broad chown to `biom3-dev-team`, `2755` dirs, `644` files), then restored the `data/nm-team-data/` override afterward.
2. **Discovered that `2775` is insufficient** for a shared multi-user subfolder — group members could `rm` each other's files. Added the **sticky bit** (`3775`) to both Profile B and the subfolder override in README.md and docs/permissions.md.
3. **Realized the user wanted the *strict* "owner-only writes" model** for `data/nm-team-data/` rather than the default collaborative model. Switched the override to use a **default ACL** (`setfacl -d`) so new files land at `644` regardless of contributor umask.
4. **Hit and fixed two cascading bugs** that came out of the ACL switch — a wrong ACL recipe that locked the owner out of newly-created subdirectories, and a kernel `CAP_FSETID` interaction that silently stripped setgid bits from `chmod`. Both are now documented in the runbook so future readers can recognize them.
5. **Created [docs/permissions.md](../permissions.md)** as a runbook covering Profile A, Profile B, and the override (with both variants), including verification queries and the gotchas above.

## Filesystem changes (no commit, applied via sudo by user)

### Broad data/ profile (Profile A — read-only for `biom3-dev-team`)

```bash
sudo chown -R ahowe:biom3-dev-team /data/data-share/BioM3-data-share/data
sudo chmod 2755 /data/data-share/BioM3-data-share/data
sudo find /data/data-share/BioM3-data-share/data -type d -exec chmod 2755 {} +
sudo find /data/data-share/BioM3-data-share/data -type f -exec chmod 644 {} +
```

The user chose Profile A so collaborators in `biom3-dev-team` can read and traverse but not modify — safer if they only ever pull from the share.

### nm-team-data override (initially collaborative `3775`/`664`, then switched to strict)

The broad chown clobbered the override done in the previous session, so it had to be re-applied:

```bash
sudo chown -R ahowe:nm-team /data/data-share/BioM3-data-share/data/nm-team-data
sudo chmod 3775 /data/data-share/BioM3-data-share/data/nm-team-data    # sticky bit added this session
sudo find /data/data-share/BioM3-data-share/data/nm-team-data -type d -exec chmod 3775 {} +
sudo find /data/data-share/BioM3-data-share/data/nm-team-data -type f -exec chmod 664 {} +
```

Then switched to strict (owner-only writes within group) after a probe file landed at `664` and the user clarified that team members should not be able to edit each other's files:

```bash
# Existing file → 644
sudo find /data/data-share/BioM3-data-share/data/nm-team-data -type f -exec chmod 644 {} +

# Default ACL so new files default to 644 even with contributor umask 002
setfacl -d -m u::rwx,g::r-x,o::r-x /data/data-share/BioM3-data-share/data/nm-team-data
# (No sudo needed — owner can setfacl their own dir.)
```

End state:

| Path | Mode | Owner:Group | Notes |
| --- | --- | --- | --- |
| `data/` | `2755` | `ahowe:biom3-dev-team` | Profile A (read-only base), setgid for group inheritance |
| `data/datasets/`, `data/weights/`, etc. | `2755` | `ahowe:biom3-dev-team` | recursive Profile A |
| files under `data/` (excluding override) | `644` | `ahowe:biom3-dev-team` | recursive Profile A |
| `data/nm-team-data/` | `3775` | `ahowe:nm-team` | strict override: setgid + sticky + group rwx |
| `data/nm-team-data/hello/` | `2755` | `ahowe:nm-team` | subdir created by user; setgid auto-inherited |
| `data/nm-team-data/hello_from_addison.txt` | `644` | `ahowe:nm-team` | strict file mode |

Default ACL on `data/nm-team-data`:

```
default:user::rwx
default:group::r-x
default:other::r-x
```

This caps new entries: files (touch requests `0666`) get `0644`, directories (mkdir requests `0777`) get `0755` with setgid auto-inherited from the parent's setgid bit → `2755`.

## Bugs encountered along the way (and what they taught us)

### Bug 1: naive default ACL locked owner out of new subdirectories

I initially gave the recipe `setfacl -d -m u::rw,g::r,o::r data/nm-team-data`, reasoning that files should be `644` and the recipe should reflect that mode directly. The user created two subdirectories inside `nm-team-data` and immediately found they couldn't `cd` into them — the directories landed at mode `0644` (no execute on any slot).

**Why it broke:** Default ACLs apply the **same mask** to both files and directories. Linux file creation requests `0666`, directory creation requests `0777`. The actual permission is the bitwise AND with the default ACL. So an ACL of `0644` gives:

| Create | Requests | AND with `0644` | Result |
| --- | --- | --- | --- |
| `touch` | `0666` | `0644` | `0644` ✓ files OK |
| `mkdir` | `0777` | `0644` | `0644` ✗ dirs unenterable |

**The fix:** use `u::rwx,g::r-x,o::r-x` (mask `0755`). Files lose the execute bits via the AND with `0666` and end up at `0644`; directories keep their execute bits and end up at `0755` (with setgid auto-inherited from parent → `2755`). The `x` bits in the default ACL exist solely to keep directories traversable.

This is now documented in [docs/permissions.md](../permissions.md) with an explicit table, plus a warning that "simplifying" the recipe to `u::rw,g::r,o::r` is the same trap.

### Bug 2: `chmod 2755` silently dropped the setgid bit

While fixing the broken `hello/` subdir, `chmod 2755` (and `chmod g+s`) returned success but `stat` immediately reported mode `0755` — no setgid bit. `strace` confirmed the `fchmodat(..., 02755)` syscall returned 0.

**Why it broke:** Linux kernel security feature `CAP_FSETID`. When a non-root process calls `chmod` to set the setgid bit on a directory, the kernel silently strips the bit if the file's group is not in the calling process's *active* group set. The chmod returns success regardless.

The catch: `ahowe` was added to the `nm-team` group earlier in the conversation, but **group membership is loaded at login**. The shell process I was running in had been started before that change, so its supplementary group set didn't include `nm-team` — even though `groups ahowe` listed it. `id` (run inside the shell) confirmed: no `nm-team`.

**The fix:** `sg nm-team -c "chmod 2755 /path/..."`. `sg` spawns a child process with the requested group added to the active set, and the kernel check passes. `sudo` would also have worked (root has `CAP_FSETID`).

This is now documented in [docs/permissions.md](../permissions.md) under "Group-membership gotcha when running chmod", with the diagnostic signature ("`chmod 2xxx` succeeds but `stat -c '%04a'` immediately reports `0xxx`") so future readers can recognize it.

## Code changes

### `README.md` — Permissions section

- **Profile B (read-write for group)** — `2775` → `3775`. Added an explanation of the setgid+sticky combination so future readers don't strip either bit thinking it's redundant.
- **Per-subfolder overrides** — `2775` → `3775`, plus a paragraph distinguishing the **collaborative** and **strict** variants and pointing at `docs/permissions.md` for the full procedure.

### `docs/permissions.md` (NEW)

New runbook for re-applying permissions on `data/`. Sections:

1. **Prerequisites** + **Order of operations** (base profile first, override second, verify)
2. **Profile A** — read-only base (`2755`/`644`)
3. **Profile B** — read-write base (`3775`/`664`) with sticky-bit explanation
4. **Subfolder override — different group** with shared explanation of setgid + sticky, then split into:
   - **Variant 1 — collaborative** (`664` files, group can edit each other's files)
   - **Variant 2 — strict** (`644` files, default ACL caveat, the corrected `setfacl -d -m u::rwx,g::r-x,o::r-x` recipe with the file/dir asymmetry table, the rsync caveat about `-a` preserving source modes)
5. **Read-only override** as a brief addendum
6. **Verification** — `find` queries for both profiles and both override variants, plus `getfacl` check for the strict variant
7. **Notes** including the new "Group-membership gotcha when running chmod" subsection covering `CAP_FSETID`

## Verification

End-to-end probes performed in `data/nm-team-data/`:

```bash
sg nm-team -c "mkdir _probe_dir && touch _probe_file && touch _probe_dir/_inner_file"
stat -c '%04a %A %U:%G %n' _probe_dir _probe_file _probe_dir/_inner_file
# 2755 drwxr-sr-x ahowe:nm-team _probe_dir
# 0644 -rw-r--r-- ahowe:nm-team _probe_file
# 0644 -rw-r--r-- ahowe:nm-team _probe_dir/_inner_file
```

The probe directory is enterable (`cd _probe_dir` succeeds), files are owner-write only, and the default ACL propagates recursively. Probes were cleaned up after.

Profile A drift checks across the rest of `data/`:

```bash
find data -type d ! -perm 2755 ! -path '*/nm-team-data*'    # empty
find data -type f ! -perm 644 ! -path '*/nm-team-data/*'    # empty
find data ! -user ahowe                                      # empty
```

All clean.

## Lingering work / not done

- **Wider project-files permissions drift** — repo root, `sync/`, `docs/`, and tracked files like `README.md` are still `775`/`664` instead of the documented `755`/`644`. The audit in the previous session note flagged this; the user explicitly chose to defer it, and that's still the state. README's "Project files" recipe is unchanged and correct, just not applied.
- **`docs/permissions.md` is not yet linked from anywhere except the inline pointer in `README.md`'s per-subfolder section.** The base profiles in README still have their recipes inline; the runbook is purely additive. This is fine — the README is for first-time setup, the runbook is for recovery — but worth noting if discoverability becomes an issue.
- **GitHub template repo conversion** still hasn't happened. The `config/` directory and gitignored-live-config pattern from the previous session were designed for it, and the new `docs/permissions.md` runbook will be useful to template instantiators, but the actual template settings haven't been flipped.
