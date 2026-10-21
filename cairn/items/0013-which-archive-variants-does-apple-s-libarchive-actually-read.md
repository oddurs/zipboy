---
id: 13
uid: d5dc2596-4820-4761-856f-c7433744fe8f
title: Which archive variants does Apple's libarchive actually read?
type: spike
status: done
milestone: v0.1
assignee: Oddur Sigurdsson
created: 2026-10-20
updated: 2026-10-20
closed_at: 2026-10-20
priority: p0
effort: s
area: archive
---

## Question

For each variant users will meet, does the libarchive in macOS 14 and 15 open it, list it, and extract it correctly? ZIP: store, deflate, deflate64, bzip2, LZMA, zstd, Zip64, data descriptors, CP437 and Shift-JIS names, backslash separators, ZipCrypto, AES-128 and AES-256. RAR4, RAR5, solid RAR5, RAR with encrypted headers. 7z: LZMA2, solid, encrypted headers. tar with gzip, bzip2, xz, zstd. cpio, ISO.

## Why it matters

The README will promise formats. Each unsupported one needs a clear message instead of a vague error, and each supported one needs a fixture.

## Timebox

One day. The answer is a support table, plus a bug item for every variant that misbehaves.

## Answer

Probed on macOS 26.5 (libarchive 3.7.4) through `Archive.extract` itself, one archive per variant holding
`hello.txt` and `dir/world.txt`. ZIP, 7z and tar variants were generated with bsdtar, Info-ZIP, Python's
zipfile and 7-Zip 26.03; RAR fixtures are libarchive's own test files (BSD-2-Clause).

| Format | Variant | Result |
|---|---|---|
| ZIP | store, deflate, bzip2, LZMA, Zip64, data descriptors, backslash separators, symlinks, empty | reads correctly |
| ZIP | ZipCrypto, AES-128, AES-256 | reads with the password; asks without it |
| ZIP | names without the UTF-8 flag (CP437) | **wrong**: `über.txt` shows as `�ber.txt` (item filed) |
| ZIP | Shift-JIS names | garbled, as expected without a way to choose the encoding (later) |
| ZIP | Deflate64 (Windows Explorer, over 2 GB) | **unsupported**: "Unsupported ZIP compression method (9)" (item filed) |
| ZIP | zstd | untested: no tool here writes it |
| RAR4 | normal, best, Unicode names | reads correctly |
| RAR5 | stored, compressed, solid, multiple solid files, Unicode, symlinks | reads correctly |
| RAR4 | encrypted data, encrypted headers | **unsupported** by libarchive, but Zipboy asks for a password forever (item filed) |
| RAR5 | encrypted | untested: no fixture; libarchive documents it as unsupported |
| 7z | LZMA, LZMA2, PPMd, BZip2, Deflate, Copy, BCJ, solid | reads correctly |
| 7z | encrypted data, encrypted headers | **unsupported** by libarchive; same password loop (item filed) |
| tar | plain, pax, gzip, bzip2, xz, lzma, zstd | reads correctly (zstd through the `zstd` program on PATH, so not on a stock Mac) |
| cpio, ISO 9660 | | reads correctly |
| single `.gz` file | | **wrong**: read as a bogus mtree listing (item filed; checked that it reads no local files without `checkfs`) |

The support table for the README is the "reads correctly" rows plus encrypted ZIP.

## Result

Support table written. Three v0.1 bugs (0054 mtree, 0055 encrypted 7z/RAR loop, 0056 CP437 names) and Deflate64 (0057, v0.2) filed.
