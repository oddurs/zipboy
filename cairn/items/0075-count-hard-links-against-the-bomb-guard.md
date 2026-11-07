---
id: 75
uid: 3da1a0f5-f844-4e54-b58f-7c61247d02c3
title: Count hard links against the bomb guard
type: bug
status: done
milestone: v0.2
assignee: Oddur Sigurdsson
created: 2026-11-01
updated: 2026-11-07
closed_at: 2026-11-07
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

- [x] A tar with one 64 MiB entry and 100 hard links to it stops at the guard, covered by a test
- [x] Ordinary hard links (`preservesHardlinksAndSkipsUnsafeOnes`) still extract

## 2026-11-07

Before the fix, HostileZipTests.stopsATarHardlinkBombAtTheExpansionGuard failed with 3 issues: 'Expected the archive to be stopped as suspicious', 'reason?.contains("decompression bomb") → nil', and link-099.bin existed after unpacking all 101 × 64 MiB (~6.46 GiB). Also found that ExpansionGuard's integer division (after / archiveBytes > 100) truncated 100.92× on an uncompressed 64 MiB + 100 hard-link tar down to 100; switched both admit and add to overflow-safe multiplication (exceedsRatio) and addingReportingOverflow. After the fix, stopsATarHardlinkBombAtTheExpansionGuard (1.36s), all 11 HostileZipTests, and ArchiveTests.preservesHardlinksAndSkipsUnsafeOnes pass.

## Result

Hard-link copies in Archive.extract now pass through ExpansionGuard.admit and ExpansionGuard.add before copying, and ExpansionGuard checks ratios with overflow-safe multiplication instead of truncating integer division so ratios just above 100:1 (such as a 64 MiB entry with 100 hard links in an uncompressed tar) stop at the guard.
