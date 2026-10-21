---
id: 24
uid: 4082c34f-1f2e-447c-b883-05f7ef3c8cbc
title: Show the version and build from the release tag in About
type: feature
status: backlog
milestone: v0.2
created: 2026-10-20
updated: 2026-10-20
priority: p2
effort: s
area: shell
---

## Problem

The About window says 0.1.0 forever, because the version is hard-coded in Info.plist.

## Proposal

`scripts/task build` writes CFBundleShortVersionString from `git describe` and CFBundleVersion from the commit count.

## Acceptance criteria

- [ ] A build on tag `v0.2.0` shows 0.2.0 in About
- [ ] A build between tags shows the next version with a `-dev` suffix and the commit count as the build
