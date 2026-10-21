---
id: 3
uid: 110c7b63-ae03-47ee-99f7-28dd0790ed5a
key: v0.3
title: Opens instantly
type: milestone
status: backlog
depends_on:
- 2
created: 2026-10-20
updated: 2026-10-20
priority: p2
due: 2027-01-29
---

## Ships

Any ZIP, however large, shows its contents in under a second and costs no disk space until a file inside is actually previewed, opened, or dragged out.

## Done when

- [ ] A 5 GB, 100,000-entry ZIP lists in under 1 second
- [ ] Opening a ZIP writes nothing to disk until an entry is used
- [ ] Long adds and extracts show progress and can be cancelled

## Explicitly not in this milestone

- Lazy opening for RAR and 7z, whose solid streams must be read in order
- Finder integration (v0.4)
