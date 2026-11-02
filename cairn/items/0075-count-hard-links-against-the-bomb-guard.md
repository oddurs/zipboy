---
id: 75
uid: 3da1a0f5-f844-4e54-b58f-7c61247d02c3
title: Count hard links against the bomb guard
type: bug
status: backlog
milestone: v0.2
created: 2026-11-01
updated: 2026-11-01
priority: p1
effort: s
area: archive
---

## What happens

## What should happen

## Reproduction

1.

## Problem

Extraction copies hard-linked entries in tar, cpio, 7z and RAR from their target without counting the
copies toward the expanded-size or ratio guards from 0069. An archive with one large entry and many
links to it expands without limit until free space runs out.

## Proposal

Count each hard-link copy toward the running expanded total, as decoded bytes are, so the same 1 GB
floor and 100:1 ratio apply.

## Acceptance criteria

- [ ] A tar with one 64 MiB entry and 100 hard links to it stops at the guard, covered by a test
- [ ] Ordinary hard links (`preservesHardlinksAndSkipsUnsafeOnes`) still extract
