---
id: 73
uid: 76137033-9f81-4edf-a01d-286ff3cdfb40
title: Stop offering to open zstd and lz4 files we can't read
type: bug
status: backlog
milestone: v0.2
created: 2026-11-01
updated: 2026-11-01
priority: p2
effort: s
area: distribution
---

## What happens

## What should happen

## Reproduction

1.

## Problem

macOS's libarchive links only zlib, liblzma and bz2lib, so zstd and lz4 archives need external tools.
Since 0071 Zipboy no longer reaches for Homebrew's, and the README says they don't open, but
`Info.plist` still declares them as documents Zipboy opens. Finder offers Zipboy for a `.tar.zst`, and
opening it fails.

## Proposal

Remove the zstd and lz4 document types from `Info.plist` and `DocumentController`, and let `BundleTests`
pin the declared set to the formats the fixture matrix proves.

## Acceptance criteria

- [ ] `Info.plist` declares no type Zipboy can't open on a stock Mac
- [ ] A `BundleTests` case fails if a declared extension has no passing fixture
