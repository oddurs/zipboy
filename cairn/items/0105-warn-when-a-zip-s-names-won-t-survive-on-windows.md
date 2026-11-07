---
id: 105
uid: 59f35577-665b-4758-bf57-86888f4eb497
title: Warn when a ZIP's names won't survive on Windows
type: feature
status: backlog
milestone: later
created: 2026-11-06
updated: 2026-11-06
priority: p3
effort: s
area: archive
---

## Problem

Mac junk is already left out of saved ZIPs, but a name holding `:` or `?`, or one such as `CON`, breaks when
the archive is opened on Windows, with no warning here.

## Proposal

Check names when saving or exporting a ZIP, and offer to replace the characters Windows rejects. Never
rename silently: the Mac is the person's own, and most archives never leave it.

## Acceptance criteria

- [ ] Names Windows rejects are detected, including reserved names and trailing dots, covered by a test
- [ ] Nothing is renamed without the person agreeing
