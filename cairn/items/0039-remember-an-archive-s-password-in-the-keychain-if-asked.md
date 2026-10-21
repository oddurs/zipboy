---
id: 39
uid: 970a84d1-b9b6-4f67-aea4-d81de940135d
title: Remember an archive's password in the Keychain, if asked
type: feature
status: backlog
milestone: v0.4
created: 2026-10-20
updated: 2026-10-20
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
- [ ] Removing the password from the archive removes the Keychain item
