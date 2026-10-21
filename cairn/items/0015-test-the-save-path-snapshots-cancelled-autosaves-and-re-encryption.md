---
id: 15
uid: fc8e59ae-b266-4d0f-8b96-8b9097441d1b
title: 'Test the save path: snapshots, cancelled autosaves, and re-encryption'
type: feature
status: done
milestone: v0.1
assignee: Oddur Sigurdsson
created: 2026-10-20
updated: 2026-10-20
closed_at: 2026-10-20
priority: p1
effort: s
area: quality
---

## Problem

Background saving snapshots the workspace, cancels stale autosaves, and re-encrypts protected archives, and none of it has a test. A regression would silently write old contents or drop the password.

## Proposal

Document tests that drive `save(to:ofType:for:)` directly against temporary files.

## Acceptance criteria

- [x] An edit made while a save runs is not in that save's file, and is in the next one
- [x] An autosave cancelled by an edit leaves the previous file intact
- [x] Saving an archive opened with a password produces AES-256 entries readable with that password
- [x] Removing the password and saving produces unencrypted entries

## 2026-10-20

Evidence: SaveTests in DocumentTests.swift drives NSDocument.save(to:ofType:for:) directly. Mutations confirm each test bites: with editsInvalidateAutosave a no-op, anEditCancelsAnAutosaveAndLeavesTheFileAlone fails (the autosave completes); with the writer ignoring the password, savesEncryptedWithThePasswordAndPlainWithout fails (entries readable without a password, no AES-256 extra field). Criterion 3 sets the password with setPassword rather than by opening an encrypted archive: opening asks through a modal sheet a test can't answer, and both paths set the same property the writer reads.

## Result

The save path has tests for snapshots, cancelled autosaves, and encryption on and off.
