---
id: 54
uid: 734948a4-9ded-4d8d-bc58-26f45e23a2ad
title: A single gzipped file opens as a bogus mtree listing
type: bug
status: backlog
milestone: v0.1
depends_on:
- 13
created: 2026-10-20
updated: 2026-10-20
priority: p2
effort: s
area: archive
---

## What happens

`Archive.extract` enables every libarchive format, including mtree, a text format for describing file trees
rather than an archive. A gzipped text file, such as `notes.txt.gz` or one renamed to `.zip`, can match it
and opens as a listing of empty entries named after its words. Found by the variant matrix: `gzip -c
hello.txt` opened as one empty entry called `hello`.

Checked and ruled out: libarchive's mtree reader takes data from files on the Mac only with the `checkfs`
option, which Zipboy never sets, so this does not leak local files. Turning mtree off still removes that
risk should a later libarchive change its default.

## What should happen

Only container formats are enabled: ZIP, 7z, RAR, RAR5, tar and its relatives, cpio, ISO 9660, and the
others libarchive reads purely from the archive's bytes. A plain gzipped file says it isn't an archive.

## Reproduction

1. `echo hello > hello.txt && gzip -c hello.txt > hello.gz`
2. Open `hello.gz` in Zipboy.
3. The list shows one empty entry, `hello`.
