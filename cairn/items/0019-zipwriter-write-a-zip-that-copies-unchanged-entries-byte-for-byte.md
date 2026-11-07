---
id: 19
uid: 60402f51-bf8a-45c4-a3f1-0c59140c145f
title: 'ZipWriter: write a ZIP that copies unchanged entries byte for byte'
type: feature
status: done
milestone: v0.2
assignee: Oddur Sigurdsson
depends_on:
- 18
created: 2026-10-20
updated: 2026-11-07
closed_at: 2026-11-07
priority: p0
effort: l
area: archive
---

## Problem

Every save recompresses every file, so a small change to a large archive costs as much as making it from scratch.

## Proposal

A writer that takes a list of entries, each either a catalog entry to copy verbatim from the source file or a workspace file to compress, and writes local headers, data, and a central directory, using Zip64 where needed. Implements what the spike chose.

## Acceptance criteria

- [x] Copied entries are byte-identical to the source's, headers included
- [x] New entries are deflated or stored by the existing `ZipMethod` rule
- [x] Output passes `unzip -t`, Archive Utility, and a re-read through ZipCatalog and libarchive
- [x] Archives over 4 GB and with over 65,535 entries round-trip
- [x] Encrypted archives follow the spike's answer, with a test

## 2026-11-01

Reconciled 2026-11-01 (0072) against the batch merged as 0063-0066. ZipWriter exists. Criterion 1: zipWriterCopiesUnchangedEntriesByteForByteAndUpdatesEditedOnes and deltaSavePreservesUnchangedEntriesByteForByteAcrossEdits; the central-directory extra fields were dropped until 0068. Criterion 5: encrypted entries are never copied verbatim (buildDeltaPlan requires password == nil), read for the purpose. Open: criterion 2 not tested against ZipMethod's rule; criterion 3 has unzip -t and libarchive but not Archive Utility; criterion 4 untested past 4 GB.

## 2026-11-07

Updated ZipWriter.writeWorkspaceItem to select Deflate vs Store from the archive entry path via ZipMethod.forFile, reserve Zip64 local headers when Deflate output near 4 GiB could cross 0xFFFF_FFFF, stamp 0x032D (Unix 4.5) in Zip64 EOCD, clamp totalWork against overflow, and stream stored/deflate/verbatim 1 MiB chunks without per-chunk Data allocations. Added ArchiveTests.zipWriterFollowsZipMethodAndPassesUnzipArchiveUtilityCatalogAndLibarchive (verifying ZipMethod across compressible, empty, precompressed, directory, and symlink items through ZipCatalog, unzip -t, ditto -x -k / Bom.framework, and libarchive) and ArchiveTests.zipWriterRoundTripsZip64OverFourGigabytesAndOverSixtyFiveThousandEntries (70,001 entries and a >4.3 GB archive with >4 GiB sizes and local/CD offsets).

## Result

ZipWriter follows ZipMethod for new entries, passes unzip -t, ditto/Bom.framework (Archive Utility's engine), ZipCatalog, and libarchive, and round-trips Zip64 archives over 4 GB and 65,535 entries.
