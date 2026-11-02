---
id: 39
uid: 970a84d1-b9b6-4f67-aea4-d81de940135d
title: Remember an archive's password in the Keychain, if asked
type: feature
status: backlog
milestone: v0.4
created: 2026-10-20
updated: 2026-11-01
priority: p3
effort: s
area: document
---

## Problem

Reopening a protected archive asks for the password every time.

## Proposal

A Remember in Keychain checkbox on the password sheet, keyed by the archive's file identifier.

## Acceptance criteria

- [ ] Checked, the next open of the same file needs no password
- [x] Removing the password from the archive removes the Keychain item

## 2026-11-01

Reconciled 2026-11-01 (0072) against the batch merged as 0063-0066. Keychain storage exists. Criterion 2: removePassword deletes the item (read for the purpose). Criterion 1 failed after any save, since items were keyed by inode and saves replace the file; 0070 (PR #26) keys them by path.
