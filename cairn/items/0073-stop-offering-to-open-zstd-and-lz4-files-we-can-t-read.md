---
id: 73
uid: 76137033-9f81-4edf-a01d-286ff3cdfb40
title: Stop offering to open zstd and lz4 files we can't read
type: bug
status: done
milestone: v0.2
assignee: Oddur Sigurdsson
created: 2026-11-01
updated: 2026-11-07
closed_at: 2026-11-07
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

- [x] `Info.plist` declares no type Zipboy can't open on a stock Mac
- [x] A `BundleTests` case fails if a declared extension has no passing fixture

## 2026-11-07

Probed stock macOS libarchive (bsdtar 3.5.3 / libarchive 3.7.4): zstd, lz4, and lzop all fail with 'Can't initialize filter; unable to run program'. Before the fix, BundleTests.everyDeclaredExtensionHasAPassingFixture failed with 7 issues: 'No passing fixture in Fixtures/matrix covers .cab / .lha / .lz4 / .lzh / .lzo / .tzst / .zst'. Removed com.facebook.zstd-archive, org.lz4.lz4-archive, and org.lzop.lzo-archive from Resources/Info.plist, removed zst/tzst/lz4/lzo from ZipMethod.archiveExtensions (used by DocumentController), removed com.github.facebook.zstd-archive from SettingsWindowController, and generated cab.cab (120 B) and lha.lha (83 B) in scripts/make-fixtures so CAB and LHA are proven by FixtureMatrixTests. After the fix, all 47 FixtureMatrixTests cases and BundleTests.everyDeclaredExtensionHasAPassingFixture pass.

## Result

Removed zstd, lz4, and lzop document types and archive extensions that stock macOS libarchive cannot decode, generated cab.cab and lha.lha fixtures in scripts/make-fixtures for CAB and LHA, and pinned every declared Info.plist and DocumentController extension to a passing matrix fixture in BundleTests.
