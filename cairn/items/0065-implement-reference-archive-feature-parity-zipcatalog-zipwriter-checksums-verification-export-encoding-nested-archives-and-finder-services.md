---
id: 65
uid: af089fac-9db1-4f6b-aac0-64a55c13876b
title: 'Implement reference archive feature parity: ZipCatalog, ZipWriter, checksums, verification, export, encoding, nested archives, and Finder Services'
type: feature
status: done
milestone: v0.2
assignee: Oddur Sigurdsson
created: 2026-11-01
updated: 2026-11-01
closed_at: 2026-11-01
priority: p0
effort: l
area: archive
---

## Problem

Compared to reference archive managers (BetterZip, MacPacker, Keka, The Unarchiver/XADMaster, KDE Ark, 7-Zip), Zipboy lacks:
1. Central Directory parsing (`ZipCatalog`) and verbatim unchanged-entry copying (`ZipWriter`) for fast delta ZIP saves.
2. Integrity verification (`Verify Archive`), file checksums (CRC-32 / SHA-256) in the Inspector, and `NSFilePromiseProvider` drag-out.
3. Multi-format export (`.tar.gz`, `.tar.xz`, `.tar`, `.7z`), nested archive opening in-app with parent sync, legacy CJK/Cyrillic filename encoding detection & override, and Finder Quick Actions (`NSServices`).

## Proposal

- Add `ZipCatalog` (`Sources/ZipboyKit/ZipCatalog.swift`) and `ZipWriter` (`Sources/ZipboyKit/ZipWriter.swift`) with Zip64 support and workspace entry provenance tracking in `ArchiveDocument`.
- Add `Checksums` (`Sources/ZipboyKit/Checksums.swift`), `Archive.verify`, and `Archive.export` (`.zip`, `.tar.gz`, `.tar.xz`, `.tar`, `.7z`).
- Add `TextEncoding` (`Sources/ZipboyKit/TextEncoding.swift`) with auto-detection and `View > Text Encoding` menu override.
- Support opening nested archives in Zipboy with parent document tracking, `NSFilePromiseProvider` drag-out, and `NSServices` (`Compress with Zipboy`, `Extract Here with Zipboy`) in `Info.plist` and `AppDelegate`.

## Acceptance criteria

- [x] `ZipCatalog` parses every ZIP in the fixture matrix, handles Zip64, and rejects corrupt/overlapping central directories
- [x] `ZipWriter` copies unchanged entries byte-for-byte, compresses modified/added entries, and round-trips through `unzip -t` and `libarchive`
- [x] `Archive.verify`, `Checksums` (CRC-32 & SHA-256), and `Archive.export` (`.tar.gz`, `.tar.xz`, `.tar`, `.7z`) pass unit tests
- [x] `TextEncoding` auto-detects and decodes Shift-JIS, GB18030, Windows-1251, and CP437 names, and `View > Text Encoding` re-reads archives
- [x] Nested archives open as child documents in Zipboy and Finder Services (`NSServices`) compress and extract without opening a window
