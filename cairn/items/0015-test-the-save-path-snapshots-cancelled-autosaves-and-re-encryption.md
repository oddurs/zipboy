---
id: 15
uid: fc8e59ae-b266-4d0f-8b96-8b9097441d1b
title: 'Test the save path: snapshots, cancelled autosaves, and re-encryption'
type: feature
status: backlog
milestone: v0.1
created: 2026-10-20
updated: 2026-10-20
priority: p1
effort: s
area: quality
---

## Problem

Background saving snapshots the workspace, cancels stale autosaves, and re-encrypts protected archives, and none of it has a test. A regression would silently write old contents or drop the password.

## Proposal

Document tests that drive `save(to:ofType:for:)` directly against temporary files.

## Acceptance criteria

- [ ] An edit made while a save runs is not in that save's file, and is in the next one
- [ ] An autosave cancelled by an edit leaves the previous file intact
- [ ] Saving an archive opened with a password produces AES-256 entries readable with that password
- [ ] Removing the password and saving produces unencrypted entries
