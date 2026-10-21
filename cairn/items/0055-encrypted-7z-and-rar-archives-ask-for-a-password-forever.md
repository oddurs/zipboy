---
id: 55
uid: 633cbc47-c21d-49cd-813d-2d35ac1280c1
title: Encrypted 7z and RAR archives ask for a password forever
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

libarchive cannot decrypt 7z or RAR archives. Zipboy treats them like encrypted ZIPs: it asks for a password,
and every answer, right or wrong, gets "Wrong password". The only way out is Cancel.

## What should happen

Zipboy says once that it can't open encrypted 7z or RAR archives, naming the format, without asking for a
password. It uses libarchive's format capabilities (`archive_read_format_capabilities`) to tell "needs a
password" from "can't be decrypted at all", so the message stays right if libarchive gains support.

## Reproduction

1. `7zz a -psecret locked.7z file.txt`
2. Open `locked.7z` in Zipboy and enter `secret`.
3. "Wrong password", repeatedly.
