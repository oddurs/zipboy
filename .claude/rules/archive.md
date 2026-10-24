---
paths:
  - "Sources/ZipboyKit/**"
  - "Sources/CArchive/**"
---

# Reading and writing archives

- `Sources/CArchive/shim.h` declares only the libarchive calls we use: macOS ships `libarchive.dylib`
  without headers. Add a declaration there, matching libarchive 3.x, before calling anything new.
- Formats are an explicit list (`Archive.formats`), never `archive_read_support_format_all`: "all"
  includes mtree, which takes text files for archives.
- Only libarchive's ZIP reader decrypts. Encrypted 7z or RAR must throw `unsupportedEncryption`, never
  ask for a password (`canDecrypt` in `Archive.swift`). The capability flags only mean "can detect".
- Names: Apple's libarchive decomposes names given to `archive_entry_set_pathname_utf8`, so the writer
  uses `archive_entry_set_pathname` with NFC names. Unflagged ZIP names are UTF-8 if valid, else CP437
  (`name(of:in:)`). The process locale is set to UTF-8 on first use.
- Extraction never trusts paths: `EntryPath.sanitized`, `linkStaysInside`, and `hasLinkAbove` guard
  against `..`, absolute paths, and stacked symlinks. Keep every new write behind them.
- Every user-facing failure is an `ArchiveError` with an `errorDescription` a person can act on.
