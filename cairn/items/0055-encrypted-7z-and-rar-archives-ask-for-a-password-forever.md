---
id: 55
uid: 633cbc47-c21d-49cd-813d-2d35ac1280c1
title: Encrypted 7z and RAR archives ask for a password forever
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

## 2026-10-23

Fixed: an encrypted entry, or a header failure that names encryption, in any format but ZIP throws unsupportedEncryption(format:) instead of asking for a password. libarchive's archive_read_format_capabilities turned out not to help: its ENCRYPT_DATA/ENCRYPT_METADATA flags mean the reader can detect encryption, and the 7z and RAR readers set them. Only the ZIP reader decrypts in libarchive 3.7, so the check is the format. saysWhenEncryptionIsUnsupported (encrypted.7z, encrypted-data.rar, encrypted-header.rar, with no password and with the right one) failed before, with passwordRequired then wrongPassword, and passes now. The app shows the reason in its existing 'couldn’t be opened' sheet.

## Result

Encrypted 7z and RAR say they can't be decrypted instead of asking for a password.
