---
id: 88
uid: ec65bbcc-c941-4552-aaa0-0b07d40dbf8d
title: Ask once for a folder's access, so writing beside an archive survives the sandbox
type: feature
status: backlog
milestone: later
depends_on:
- 46
created: 2026-11-02
updated: 2026-11-02
priority: p3
effort: m
area: distribution
---

## Problem

Under the App Sandbox, opening an archive grants access to that file only. Extracting next to it,
the Compress with Zipboy service, and Extract Here all write into its folder, which nobody granted
(0046).

## Proposal

When a write needs a folder the app can't reach, show an open panel on that folder ("Allow Zipboy to
save next to this archive"), keep a security-scoped bookmark for it, and use the bookmark from then
on. Only worth doing if Zipboy goes to the Mac App Store.

## Acceptance criteria

- [ ] In a sandboxed build, the first extract beside an archive asks once for the folder, and the second asks nothing
- [ ] A revoked or stale bookmark asks again instead of failing silently
