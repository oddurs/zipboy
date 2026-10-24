---
id: 56
uid: 66f149ec-de9a-4a3f-a6a9-31713aeddca6
title: Names in old ZIPs without the UTF-8 flag show as �
type: bug
status: done
milestone: v0.1
assignee: Oddur Sigurdsson
depends_on:
- 13
created: 2026-10-20
updated: 2026-10-23
closed_at: 2026-10-23
priority: p1
effort: s
area: archive
---

## What happens

ZIPs made by older Windows tools store names in code page 437 without the UTF-8 flag. Zipboy decodes them as
UTF-8, so `über.txt` (stored as `0x81 ber.txt`) shows as `�ber.txt`, and saving writes the mangled name back.

## What should happen

A name that is valid UTF-8 is read as UTF-8, since macOS's own tools write UTF-8 without setting the flag.
Any other name is read as CP437, as the ZIP specification says. `über.txt` shows as `über.txt`.

## Reproduction

1. Make a ZIP whose entry name is the bytes `81 62 65 72 2e 74 78 74` with general-purpose bit 11 clear.
2. Open it in Zipboy.
3. The entry reads `�ber.txt`.

## 2026-10-23

Fixed: for ZIP entries, Archive.extract takes the stored name bytes (archive_entry_pathname) and reads them as UTF-8 when valid, otherwise as code page 437. readsCodePage437NamesFromOldZips (0x81 'ber.txt', UTF-8 flag clear) failed before with '�ber.txt' and passes now; readsUnflaggedUTF8NamesAsUTF8 (UTF-8 bytes, flag clear, as macOS tools write) passed before and after. Shift-JIS names now read as CP437 lookalikes instead of '�': still wrong, and still the 'later' encoding item.

## Result

Unflagged ZIP names that aren't UTF-8 read as CP437.
