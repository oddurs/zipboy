---
id: 13
uid: d5dc2596-4820-4761-856f-c7433744fe8f
title: Which archive variants does Apple's libarchive actually read?
type: spike
status: backlog
milestone: v0.1
created: 2026-10-20
updated: 2026-10-20
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
