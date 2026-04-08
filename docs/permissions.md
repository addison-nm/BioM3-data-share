# Permissions runbook for `data/`

Recipes for re-applying ownership and permissions on `data/` and its
subdirectories. Use this when permissions have drifted from the documented
profile, after a fresh clone, or whenever you need to combine a base profile
with a per-subfolder group override.

For project files outside `data/` (repo root, `sync/`, `docs/`, etc.), see
the [Permissions section in README.md](../README.md#permissions).

## Prerequisites

- `sudo` access on the host
- Target group(s) exist in `/etc/group` — verify with `getent group <group-name>`
- A clear answer to: do collaborators in the project group need read-write
  on `data/`, or just read?

## Order of operations

When applying both a base profile and per-subfolder overrides, **always
apply the base profile first** and re-apply overrides after. The recursive
chown in the base step will clobber any subfolder-specific group ownership.

```text
1. base profile        (chown -R + chmod across all of data/)
2. subfolder override  (chown -R + chmod scoped to data/<subfolder>)
3. verify              (find queries below)
```

## Profile A — read-only base

Group members can read and traverse but cannot modify. Only `<owner>` can write.

```bash
sudo chown -R <owner>:<project-group> data
sudo chmod 2755 data
sudo find data -type d -exec chmod 2755 {} +
sudo find data -type f -exec chmod 644 {} +
```

## Profile B — read-write base

Group members can create and modify files anywhere under `data/`. The
sticky bit ensures users can only delete or rename files they own — a
non-owner cannot remove someone else's file even though they have group
write on the parent directory.

```bash
sudo chown -R <owner>:<project-group> data
sudo chmod 3775 data
sudo find data -type d -exec chmod 3775 {} +
sudo find data -type f -exec chmod 664 {} +
```

## Subfolder override — different group

Apply *after* one of the base profiles to grant a non-project group access
to a single subfolder. Example: give `my-team` access to
`data/my-team-data/`. The directory recipe is the same in both variants
below — they differ only in the *file* mode and how new files inherit it.

In both variants the directory uses mode `3775`, which combines two
special bits that do different jobs. Both are needed for a shared
multi-user subfolder, and stripping either one is almost always a mistake:

- **setgid (`2`)** — new files and subdirectories created here inherit the
  directory's group (`my-team`) instead of the creating user's primary
  group. Without it, a `my-team` member's file lands with their personal
  group and other team members lose access entirely.
- **sticky (`1`)** — only a file's owner (or root, or the directory
  owner) can delete or rename a file. Without it, *any* `my-team` member
  can `rm` files owned by other members, because Linux delete permission
  is governed by the parent directory's write bit, not the file's own
  permissions. This is the same protection `/tmp` uses.

Note that the sticky bit only protects against delete and rename — it does
**not** prevent group members from modifying file *contents*. That is
controlled by the file mode, which is what the two variants below differ
on.

### Variant 1 — collaborative (group can edit each other's files)

Files are group-writable (`664`). Any `my-team` member can open and edit
any file in the subfolder; the sticky bit still prevents them from
deleting or renaming files they don't own. Use this when the team is
genuinely co-editing a shared dataset, document set, or notebook.

```bash
sudo chown -R <owner>:my-team data/my-team-data
sudo chmod 3775 data/my-team-data
sudo find data/my-team-data -type d -exec chmod 3775 {} +
sudo find data/my-team-data -type f -exec chmod 664 {} +
```

This is the default if your users have `umask 002` — new files will
naturally land at `664` and match the recipe with no extra config.

### Variant 2 — strict (owner-only writes within group)

Files are owner-write only (`644`). Each team member can write to files
they own, and other members get read access. Combined with the sticky
bit, this means each member maintains their own files: nobody can edit
or delete anyone else's. Use this when the subfolder is more like a
shared sandbox with personal scratch space than a co-edited workspace.

```bash
sudo chown -R <owner>:my-team data/my-team-data
sudo chmod 3775 data/my-team-data
sudo find data/my-team-data -type d -exec chmod 3775 {} +
sudo find data/my-team-data -type f -exec chmod 644 {} +
```

**Umask caveat.** If your users have `umask 002` (common on shared
machines), the recipe above is not enough on its own. As soon as a user
creates a new file, their umask will produce mode `664` and break the
strict invariant. There are two ways to enforce `644` regardless of user
umask:

1. **Default ACL on the subfolder (recommended).** Linux default ACLs let
   you cap the perms of newly-created entries inside a directory,
   independent of each user's umask. Requires the `acl` package
   (`apt install acl` on Debian/Ubuntu).

   ```bash
   sudo setfacl -d -m u::rwx,g::r-x,o::r-x data/my-team-data
   ```

   This may look surprising — the goal is `644` files, but the recipe
   uses `rwx`/`r-x`/`r-x`. The reason is that **default ACLs apply the
   same mask to both files and directories**, but file creation
   (`touch`, `>`) requests mode `0666` while directory creation (`mkdir`)
   requests `0777`. The actual permission is the bitwise AND:

   | Create | Requests | Default ACL `0755` cap | Result |
   | --- | --- | --- | --- |
   | `touch new.txt` | `0666` | `0755` | **`0644`** ✓ files strict |
   | `mkdir new_dir` | `0777` | `0755` | **`0755`** ✓ dirs traversable |

   If you naively use `u::rw,g::r,o::r` (mask `0644`), files come out
   correct but **new subdirectories land at `0644` with no execute bit
   on any slot — owners can't even `cd` into directories they just
   created**. The `x` bits in the default ACL exist solely to give
   subdirectories the traversal they need; files lose their `x` for free
   because `touch`/`>` never request it.

   New files in `data/my-team-data` will now land at `644` even when the
   creating user has `umask 002`, and new subdirectories will land at
   `2755` (setgid auto-inherited from the parent's setgid bit). The
   parent directory's own mode bits stay at `3775` — `setfacl -d` only
   affects the *default ACL* that new entries inherit, not the directory
   itself. `ls -ld` will show a `+` suffix on the mode column to
   indicate a default ACL is present.

   To verify: `getfacl data/my-team-data` should show `default:user::rwx`,
   `default:group::r-x`, `default:other::r-x` lines.

2. **Per-user umask discipline.** Each contributor runs `umask 022` in
   their shell before working in the subfolder. Fragile in practice
   because it relies on every contributor remembering, and it doesn't
   solve the file/dir asymmetry — prefer the default ACL approach.

**Group-membership gotcha when running chmod.** If you've just been
added to the override group (`my-team`), your *existing* shell sessions
do not yet have it in their active group set — group membership is
loaded at login. When a non-root process calls `chmod` to set the
setgid bit on a directory, the kernel **silently strips the setgid bit
if the file's group is not in the calling process's group set**. The
chmod returns success but the bit never sticks.

This is the standard Linux `CAP_FSETID` security feature, not a bug.
Workarounds:

- **`sudo`** — root bypasses the check entirely. Easiest if you have it.
- **`sg my-team -c "chmod ..."`** — runs the chmod in a temporary
  process with `my-team` added to the group set, no root needed.
- **Re-login** — open a fresh shell so the new group membership is
  loaded normally.

If you find that `chmod 2xxx data/my-team-data/something` succeeds but
`stat -c '%04a'` immediately reports `0xxx` (no leading `2`), this is
the cause.

**rsync caveat.** `rsync -a` preserves source modes and will not have
its modes capped by the default ACL. This is generally fine for
`my-team-data` because the [biom3sync excludes file](../config/excludes.example)
should already list it (it's a per-team subfolder, not part of the
shared data set replicated across clusters). If you do rsync into a
strict subfolder from elsewhere, you'll need `--chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r`
or a post-sync chmod pass.

### Read-only override

For a *read-only* override on a subfolder (rare — usually you'd just use
the read-only base profile), swap `3775` → `2755` and `664`/`644` → `644`.
No sticky bit is needed when the group can't write at all.

## Verification

After applying, confirm the end state matches the profile. Empty output
from the `find` commands means no drift.

```bash
# Top-level spot check
stat -c '%a %U:%G %n' data data/my-team-data

# Find any directory that drifted from the base profile mode (excluding overrides)
find data -type d ! -perm 2755 ! -path '*/my-team-data*'    # Profile A
find data -type d ! -perm 3775 ! -path '*/my-team-data*'    # Profile B

# Find any file that drifted from the base profile mode (excluding overrides)
find data -type f ! -perm 644 ! -path '*/my-team-data/*'    # Profile A
find data -type f ! -perm 664 ! -path '*/my-team-data/*'    # Profile B

# Override subfolder — directories should be 3775 in either variant
find data/my-team-data -type d ! -perm 3775

# Override subfolder — file mode depends on which variant you chose
find data/my-team-data -type f ! -perm 664    # Variant 1 (collaborative)
find data/my-team-data -type f ! -perm 644    # Variant 2 (strict)

# Confirm the override subfolder has the right group throughout
find data/my-team-data ! -group my-team

# For Variant 2: confirm the default ACL is in place
getfacl data/my-team-data | grep '^default:'
```

If you have multiple override subfolders, repeat the override block and
the override-group `find` for each, and extend the `! -path` exclusions in
the base-profile drift checks to skip them all.

## Notes

- The recursive chown is safe on files currently being read; ongoing reads
  will not break.
- Files mid-write (active rsync, in-progress download) will land with the
  new perms — usually fine, but worth knowing if a long-running sync is
  in flight.
- The walk over `data/` can take a moment on a large share, but no file
  contents are touched.
- If a base-profile drift check returns hits *inside* an override
  subfolder, you forgot to re-apply the override after the base step —
  re-run the override block.
