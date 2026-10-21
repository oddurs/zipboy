---
id: 17
uid: b4b4bca9-a377-43f5-a4b0-58f643ab13fe
title: 'Copy unchanged ZIP entries verbatim: our own writer, or libarchive?'
type: spike
status: backlog
milestone: v0.2
created: 2026-10-20
updated: 2026-10-20
priority: p0
effort: s
area: archive
---

## Question

libarchive cannot pass compressed data through, so every save recompresses everything. Is a minimal ZIP writer in Swift the answer: local headers, data descriptors, Zip64, the central directory, raw deflate for new entries through zlib or the Compression framework? What happens to AES entries: can they be copied as they are, and can we encrypt new ones with CommonCrypto (PBKDF2, AES-CTR, HMAC-SHA1)?

## Why it matters

Saving a 2 GB archive takes about a minute today. This decides the design of the whole milestone.

## Timebox

One day, ending in a prototype that copies one entry verbatim and adds one new entry, readable by `unzip -t` and Archive Utility.

## Answer
