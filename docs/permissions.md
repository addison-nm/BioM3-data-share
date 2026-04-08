# Permissions runbook for `data/`

Recipes for re-applying ownership and permissions on `data/` and its subdirectories. Use this after a fresh clone, when permissions have drifted, or when adding a new override subfolder.

For project files outside `data/` (repo root, `sync/`, `docs/`, etc.), see the [Permissions section in README.md](../README.md#permissions).

## Prerequisites

- `sudo` access on the host
- Target group(s) exist in `/etc/group` — verify with `getent group <group-name>`
- A clear answer to: do collaborators in the project group need read-write on `data/` itself, or just read?

## Order of operations

When applying both a base profile and per-subfolder overrides, **always apply the base profile first** and re-apply each override afterward. The recursive `chown` and `chmod` in the base step will clobber any subfolder-specific group ownership.

```text
1. base profile        (chown -R + chmod across all of data/)
2. each override       (chown -R + chmod scoped to data/<subfolder>)
3. verify              (find queries below)
```

## Profile A — group read-only base (canonical)

The project group can read and traverse everything under `data/`. Only the owner can write. This is the default profile for BioM3-data-share, since `data/` is populated by the owner via `biom3sync` rather than by collaborators writing directly.

```bash
sudo chown -R <owner>:<project-group> data
sudo chmod 2755 data
sudo find data -type d -exec chmod 2755 {} +
sudo find data -type f -exec chmod 644 {} +
```

The setgid bit (`2`) on directories ensures new entries inherit the project group rather than the creator's primary group. No default ACL is needed: with group mode `r-x`, there is no group write bit for umask masking to silently strip.

## Lockdown override for a subfolder — group-only access

Carve out a subfolder where exactly one group has read-write access and everyone else (including the project group) has nothing. Apply this *after* the base profile.

```bash
sudo chown -R :<team> data/<team>-data
sudo chmod 3770 data/<team>-data
sudo find data/<team>-data -mindepth 1 -type d -exec chmod 2770 {} +
sudo find data/<team>-data -type f -exec chmod 660 {} +
sudo setfacl -k data/<team>-data
sudo setfacl -d -m u::rwx,g::rwx,o::--- data/<team>-data
```

What each piece does:

- **`chown -R :<team>`** — only changes the group, leaves the user owner alone. This matters because `<team>` members create files inside the override; reapplying the recipe should not flatten everyone's user ownership to a single account.
- **`chmod 3770` on the override root** — `3` is setgid + sticky. Setgid makes new entries inherit `<team>` as their group; sticky makes only a file's owner (or root) able to delete or rename top-level entries inside the override. `770` gives owner and group full access and other nothing — non-`<team>` users cannot even `ls` the directory.
- **`chmod 2770` on nested directories** — same setgid behavior, no sticky. The sticky bit does not propagate via `mkdir`, so subdirectories created inside the override land at `2770` no matter what; this is the same mode applied here. The trade-off is that any team member can `rm` entries inside nested directories, just not at the top level.
- **`chmod 660` on files** — owner and group rw, other nothing.
- **`setfacl -k`** — removes any pre-existing default ACL on the override root so the next line is the only default in effect.
- **`setfacl -d -m u::rwx,g::rwx,o::---`** — installs a default ACL so newly-created entries inherit `g::rwx` regardless of each contributor's umask. Without this, a contributor with `umask 022` would create files at `640` and directories at `2750` — group-readable but not writable, which silently breaks the override.

After applying, members of `<team>` can create arbitrarily nested files and directories anywhere under the override. Anyone else, including members of the project group, gets `Permission denied` even on `ls`.

### Limitations to know about

- **Editing each other's files is allowed.** Mode `660` means any `<team>` member can modify the contents of any file, not just files they own. The sticky bit only blocks delete and rename on the override root, not content modification anywhere. POSIX ACLs on Linux ext4 cannot enforce "files owner-write only, dirs group-write" because the same default ACL mask applies to both. If you need stricter enforcement, you'd need NFSv4 ACLs or a periodic chmod sweep.
- **Sticky doesn't propagate to nested subdirectories.** Top-level entries in the override are sticky-protected, but new subdirectories inside (`<team>-data/foo/`) land at `2770` without the sticky bit, so any team member can `rm` entries inside them.

## Profile B — group read-write base (alternative)

If collaborators in the project group need to write directly to `data/` itself (not just to an override subfolder), use this in place of Profile A. It requires the same default ACL as the lockdown override, for the same reason: `umask 022` would otherwise silently strip group write from new entries.

```bash
sudo chown -R <owner>:<project-group> data
sudo chmod 3775 data
sudo find data -type d -exec chmod 3775 {} +
sudo find data -type f -exec chmod 664 {} +
sudo setfacl -k data
sudo setfacl -d -m u::rwx,g::rwx,o::r-x data
```

Setgid (`2`) makes new entries inherit the project group. Sticky (`1`) blocks delete and rename of top-level entries by non-owners. The default ACL forces new files to land at `664` and new directories at `3775`. Same caveat as the override: sticky does not propagate via `mkdir`, so the delete-protection guarantee silently degrades for any directories created after the sweep.

## Verification

Empty output from each `find` means no drift.

```bash
# Top-level spot check
stat -c '%a %U:%G %n' data data/<team>-data

# Drift check against Profile A (excluding the override)
find data -type d ! -perm 2755 ! -path '*/<team>-data*'
find data -type f ! -perm 644 ! -path '*/<team>-data*'

# Override root — should be 3770
find data/<team>-data -maxdepth 0 ! -perm 3770

# Nested directories inside the override — should be 2770
find data/<team>-data -mindepth 1 -type d ! -perm 2770

# Files inside the override — should be 660
find data/<team>-data -type f ! -perm 660

# Group should be <team> throughout the override
find data/<team>-data ! -group <team>

# Default ACL should show o::---
getfacl data/<team>-data | grep '^default:'
```

If you have multiple override subfolders, repeat the override block and the override-group `find` for each, and extend the `! -path` exclusions in the base-profile drift checks to skip them all.

## Notes

- The recursive `chown` is safe on files currently being read; ongoing reads will not break.
- Files mid-write (active rsync, in-progress download) will land with the new permissions — usually fine, worth knowing if a long-running sync is in flight.
- The walk over `data/` can take a moment on a large share, but no file contents are touched.
- **rsync caveat for override subfolders.** `rsync -a` preserves source modes and is not capped by the default ACL. Per-team override subfolders should already be excluded from `biom3sync` via [config/excludes](../config/excludes.example). If you do rsync into one from elsewhere, pass `--chmod=Du=rwx,Dg=rwx,Do=,Fu=rw,Fg=rw,Fo=` or run a post-sync chmod pass to restore the lockdown.
- **Group-membership chmod gotcha.** If you've just been added to the override group and your shell session predates that change, a non-root `chmod` to set setgid will silently succeed without actually setting the bit. Use `sudo` (root bypasses the check), `sg <group> -c "chmod ..."` (runs in a temporary process with the group added), or open a fresh shell so the new group membership is loaded.
