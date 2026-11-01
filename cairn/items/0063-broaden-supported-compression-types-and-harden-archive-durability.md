---
id: 63
uid: 27906e6c-a893-4345-a65e-7c3e71da4395
title: Broaden supported compression types and harden archive durability
type: feature
status: done
milestone: v0.2
assignee: Oddur Sigurdsson
created: 2026-11-01
updated: 2026-11-01
closed_at: 2026-11-01
priority: p1
area: archive
effort: m
---

## Problem

1. Several common compression and archive types are either rejected or not mapped by the app:
   - Deflate64 ZIPs (method 9, written by Windows Explorer for large files) fail in libarchive.
   - `Info.plist` and `DocumentController` omit UTTypes and extensions for `.tbz`/`.tbz2`, `.txz`, `.tlz`, `.tzst`, `.taz`, `.Z`, `.cpgz`, `.xar`, `.pkg`, `.cab`, `.lha`/`.lzh`, `.ar`/`.deb`, `.zipx`, `.cbz`, `.cbr`, `.cb7`, `.jar`, `.war`, `.ipa`, `.apk`, `.whl`, `.xpi`, `.nupkg`, and GUI launches lack `/opt/homebrew/bin` and `/usr/local/bin` on `PATH` for external filters (`zstd`, `lz4`).
   - Compound archive names such as `project.tar.gz` keep `.tar` in their suggested draft and extracted folder names.
   - XAR archives extracted through `archive_read_data` receive trailing NUL bytes after the first entry due to libarchive's cumulative EOF offset.
2. Durability gaps:
   - Hardlink entries in `tar`, `cpio`, `7z`, and `rar` (including `rar5-unicode.rar`) have no stream of their own, so `Archive.extract` either skips them or writes 0-byte files.
   - Free space is checked only against the entry header's declared size before reading, not per chunk during decompression, and failed or cancelled mid-file writes leave partial files behind.
   - `Archive.writeZip` opens the destination path directly instead of writing to a sibling staging file, flushing (`fsync`), and atomically renaming into place.
   - Read-only folders and files (`0o555` / `0o444`, as from a mounted DMG or ISO) added into a workspace retain read-only permissions and cannot be renamed or deleted.

## Proposal

- Add a built-in `Deflate64` decoder (`Sources/ZipboyKit/Deflate64.swift`) that decodes method-9 ZIP entries with a 64 KB sliding window and verifies their CRC-32 and uncompressed length.
- Broaden `Info.plist`, `DocumentController.typeForContents(of:)`, `ZipMethod`, and `Naming.stem(of:)`, add Homebrew paths to `PATH` for external filters, and add fixtures (`zip-xz.zip`, `zip-ppmd.zip`, `tar-compress.tar.Z`, `tar-uu.tar.uu`, `cpio-gz.cpgz`, `xar.xar`, `ar.ar`) to `scripts/make-fixtures` and `FixtureMatrixTests`.
- Bound XAR reads to the declared entry size so libarchive does not zero-pad entries after the first.
- Preserve safe hardlinks inside the extraction root, check free space on every decompressed chunk, remove partial files on any extraction failure or cancellation, make `Archive.writeZip` atomic via a `fsync`ed staging file + `rename(2)`, and ensure items copied into a workspace have owner-writable permissions.

## Acceptance criteria

- [x] `zip-deflate64.zip`, `zip-xz.zip`, `zip-ppmd.zip`, `tar-compress.tar.Z`, `tar-uu.tar.uu`, `cpio-gz.cpgz`, `xar.xar`, and `ar.ar` open and pass `FixtureMatrixTests`
- [x] Hardlinks inside archives (such as `tar` and `rar5-unicode.rar`) preserve their target's contents when staying inside the root
- [x] Mid-stream capacity exhaustion stops extraction and removes partial files, and a cancelled `Archive.writeZip` leaves an existing destination archive untouched
- [x] Read-only folders and files added to a document become editable and removable in the workspace
- [x] `Info.plist`, `DocumentController`, `ZipMethod`, and `Naming.stem(of:)` cover the expanded set of archive extensions and compound names

## 2026-11-01

Added Deflate64 decoder in Sources/ZipboyKit/Deflate64.swift; expanded Info.plist UTTypes, DocumentController.typeForContents(of:), ZipMethod, and Naming.stem(of:); bounded XAR entry reads to prevent libarchive post-EOF NUL padding; preserved safe hardlinks in Archive.extract; enforced per-chunk free-space checks and partial-file cleanup; made Archive.writeZip atomic with staging file + fsync + rename; ensured Workspace.makeWritable on added items; expanded fixture matrix to 45 archives and test suite to 50 tests.

## Result

Zipboy now opens Deflate64, XZ/PPMd ZIPs, .tar.Z, .tar.uu, .cpgz, XAR, ar, CAB, LHA, and related archive extensions, while preserving hardlinks, enforcing mid-stream space limits, cleaning up partial extractions, and writing ZIPs atomically.

## 2026-11-01

Reverted yellow/orange UI theme to native macOS system accent colors and standard selection, refined outline view to inset Finder style with alternating row stripes and crisp typography, and redesigned inspector with a Finder-style Information table while keeping the manga running Zipboy app icon.
