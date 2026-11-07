---
id: 101
uid: 7466602e-0475-4d11-8485-f3655791c269
title: Try saved passwords on a new archive
type: feature
status: backlog
milestone: later
created: 2026-11-06
updated: 2026-11-06
priority: p3
effort: s
area: document
---

## Problem

The same password often opens every archive from one source, but the Keychain only knows it per file.

## Proposal

A short list of remembered passwords in the Keychain, tried in order before asking, only ever when the
person opted in by saving one for reuse. ZIP only, since it's all libarchive can decrypt.

## Acceptance criteria

- [ ] An archive that opens with a saved password shows no prompt
- [ ] A wrong password stops after the saved list and asks once, covered by a test
- [ ] Nothing is saved for reuse unless the person says so
