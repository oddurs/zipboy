---
id: 56
uid: 66f149ec-de9a-4a3f-a6a9-31713aeddca6
title: Names in old ZIPs without the UTF-8 flag show as �
type: bug
status: backlog
milestone: v0.1
depends_on:
- 13
created: 2026-10-20
updated: 2026-10-20
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
