# BioM3-data-share — TODO

Running list of work items collected from teammate feedback (2026-04-08). Check items off (`[x]`) as they land and add a short note linking the PR / commit.

---

## General

- [ ] **Versioning** — confirm BioM3-data-share has an appropriate version source of truth and that it is current.
- [ ] **BioM3 paper reference** — audit [README.md](README.md) and ensure the correct BioM3 citation is used.
- [ ] **Sync log** — refresh [SYNC_LOG.md](SYNC_LOG.md) with the current paired commit hash against BioM3-dev.
- [ ] **Service-account owner for `data/`** — evaluate replacing `ahowe` as the canonical owner of `data/` with a `biom3-data-manager` system account, gated behind a `biom3-admins` sudoers group. Defer until one of: (a) a second human needs to do owner-side maintenance, (b) audit logs need project identity instead of personal identity, (c) ownership handoff at project rotation, (d) `biom3sync` pushes from a non-`ahowe` account. Switch is mechanically a recursive `chown` plus a one-word substitution in [docs/permissions.md](docs/permissions.md); modes and ACLs do not change.

---

## Documentation

- [ ] **Writing to non-synced shared points** — document the workflow for writing to shared points under `data/` that are excluded from rclone sync.

---

## Data checks

- [ ] **Audit `data/datasets/Stage2_embeddings`** — verify the current embedding files there are correct and complete.

---

## Adding to this list

When new feedback comes in:
1. Drop it under the matching `##` section (or create a new one).
2. Use a checkbox (`- [ ]`) and a one-line summary; add follow-up details on indented bullets.
