---
id: 71
uid: c587d677-2696-4b51-ac5a-65091c2eb0af
title: Export keeps encryption, and archive I/O stays off shared state
type: bug
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

Findings 7, 10, 11, and 12 of the 2026-11-01 review of the four merged batches:

1. Exporting a password-protected archive as tar.gz, tar.xz, tar, or 7z writes every file in plaintext
   without a word. Only the ZIP writer can encrypt.
2. Choosing a text encoding decodes every ZIP name with it, even names the archive flags as UTF-8.
   `ZipCatalog` honours the flag, so the catalog's paths stop matching the workspace and delta saves
   quietly stop. `Deflate64.locateEntry` always decodes with Automatic, so a Deflate64 entry with a
   non-ASCII name can't be found under a chosen encoding.
3. Saves and exports flush with plain `fsync`, which on macOS doesn't reach the platter, ignore its
   result, and never flush the folder after the rename. `Node.fromCatalog` has no caller outside tests.
4. The first archive call runs `setenv("PATH", …)` from whatever thread it lands on, racing every other
   reader of the environment, so libarchive can exec Homebrew's zstd and lz4. No format the app claims
   needs them. The Finder Services handlers copy and zip, or unpack, on the main thread.

## Proposal

- `Archive.export` refuses a password for any format but ZIP with a new `ArchiveError.cantEncrypt`, and
  the export panel disables those formats when the document has a password.
- `name(of:in:encoding:)` decodes names in the ZIP's UTF-8 set (read from the central directory) as
  UTF-8 under a chosen encoding, and `Deflate64.locateEntry` decodes with the chosen encoding and the
  entry's flag, the way `ZipCatalog` does.
- One helper flushes with `F_FULLFSYNC`, throws when it fails, renames, and flushes the parent folder;
  `writeZip`, `export`, and `ZipWriter.write` use it. `Node.fromCatalog` and its test uses go.
- Drop the `PATH` mutation. Services run on a detached task and report failures in an alert.

## Acceptance criteria

- [x] `Archive.export` with a password throws `ArchiveError.cantEncrypt` for tar.gz, tar.xz, tar, and 7z, leaves no file behind, and still encrypts ZIP; a test covers each format
- [x] Under a chosen encoding, a UTF-8-flagged ZIP name extracts as UTF-8 and matches `ZipCatalog`'s path; a test fails without the fix
- [x] A Deflate64 entry whose unflagged name decodes differently under the chosen encoding extracts under that encoding; a test fails without the fix
- [x] `writeZip`, `export`, and `ZipWriter.write` flush with `F_FULLFSYNC`, fail on a flush error, and flush the parent folder after the rename
- [x] `Node.fromCatalog` is gone and nothing refers to it
- [x] No code calls `setenv`, and the README says zstd and lz4 don't open
- [x] The Finder Services handlers do their work off the main thread and show failures in an alert; a test shows the work runs off the main thread
- [x] `scripts/task check` passes

## 2026-11-01

Before the fix, refusesToExportAPasswordToAFormatThatCannotKeepIt failed for all four formats (tar, tar.gz, tar.xz, 7z): 'an error was expected but none was thrown', and the plaintext file existed at the destination. exportsAPasswordToZipEncrypted passed: ZIP already encrypts.

## 2026-11-01

Before the fix, keepsFlaggedNamesUTF8UnderAChosenEncoding failed: under CP437 the flagged name extracted as 'u╠êber.txt' while ZipCatalog said 'über.txt'. libarchive hands back flagged names as NFD UTF-8 (75 CC 88) while the central directory stores NFC (C3 BC), so the flagged set has to be compared as text, not bytes. A first version under Shift-JIS passed by luck: NSString rejects those NFD bytes as Shift-JIS and decode falls back to UTF-8.

## 2026-11-01

Before the fix, findsDeflate64EntriesUnderAChosenEncoding failed with unreadable('Unsupported ZIP compression method (9: deflation-64-bit)'): libarchive named the entry '├╝g.txt' under CP437, locateEntry decoded the same bytes with Automatic as 'üg.txt', found nothing, and the extraction fell back to libarchive's error.

## 2026-11-01

runsFinderServicesOffTheMainThread could not fail at runtime before the fix: the handlers did their work inline with no seam to observe, so before the fix it failed to compile ('AppDelegate has no member runService'). The old handlers ran on the main thread by construction (@MainActor class, synchronous body).

## 2026-11-01

After the fix: refusesToExportAPasswordToAFormatThatCannotKeepIt (4 cases), exportsAPasswordToZipEncrypted, keepsFlaggedNamesUTF8UnderAChosenEncoding, findsDeflate64EntriesUnderAChosenEncoding, and runsFinderServicesOffTheMainThread all pass; scripts/task check passed with 72 tests in 13 suites.

## 2026-11-01

F_FULLFSYNC and the folder flush have no test: a test can't observe whether a write reached the platter, and faking fcntl would test the fake. Every save and export in the suite now runs through Archive.commit, so a flush that threw on APFS would fail them. F_FULLFSYNC falls back to fsync on any failure, as SQLite does, since FAT and network volumes refuse it; the folder flush tolerates ENOTSUP, EINVAL, and EACCES because the archive is already durable and renamed by then.

## 2026-11-01

zstd and lz4: the libarchive in macOS 3.7.4 links only zlib, liblzma, and bz2lib (bsdtar --version), so both run as external programs, and a stock Mac has neither. No fixture or README row claims them, so the PATH mutation went rather than moving to launch; the README now says they don't open. Info.plist still declares zstd and lz4 document types; left alone as outside this item. setlocale(LC_CTYPE) stays in the lazy static: names need it, and moving it to launch would leave ZipboyKit's tests without it.

## 2026-11-01

Services: the handlers now return at once and run the work on a detached task; failures show the Prompts.makeErrorAlert alert after activating the app. The error out-parameter is no longer set, since it is read only before the handler returns. The alert path itself has no test: a modal alert would hang the suite.

## Result

Export refuses a password for every format but ZIP with ArchiveError.cantEncrypt, and the export panel disables those formats when the document has one. Under a chosen encoding, names a ZIP flags as UTF-8 stay UTF-8 (matched as text, since libarchive returns them decomposed), and Deflate64 lookup decodes with the chosen encoding and the flag. Archive.commit flushes with F_FULLFSYNC, throws on failure, renames, and flushes the folder; writeZip, export, and ZipWriter.write use it. The PATH mutation is gone, since no claimed format needs zstd or lz4, and so is Node.fromCatalog. Finder Services run on a detached task and show failures in an alert.
