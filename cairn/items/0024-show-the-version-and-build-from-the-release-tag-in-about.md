---
id: 24
uid: 4082c34f-1f2e-447c-b883-05f7ef3c8cbc
title: Show the version and build from the release tag in About
type: feature
status: backlog
milestone: v0.2
created: 2026-10-20
updated: 2026-11-01
priority: p2
effort: s
area: shell
---

## Problem

The About window says 0.1.0 forever, because the version is hard-coded in Info.plist.

## Proposal

`scripts/task build` writes CFBundleShortVersionString from `git describe` and CFBundleVersion from the commit count.

## Acceptance criteria

- [x] A build on tag `v0.2.0` shows 0.2.0 in About
- [ ] A build between tags shows the next version with a `-dev` suffix and the commit count as the build

## 2026-11-01

Reconciled 2026-11-01 (0072) against the batch merged as 0063-0066. scripts/task build stamps CFBundleShortVersionString from an exact tag (criterion 1). Criterion 2 is not met: between tags it stamps the previous tag plus -dev (0.1.0-dev after v0.1.0), not the next version.
