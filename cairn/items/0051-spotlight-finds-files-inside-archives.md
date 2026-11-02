---
id: 51
uid: 9f1ffc0d-b8f1-438f-802a-ff61441b456c
title: Spotlight finds files inside archives
type: feature
status: blocked
milestone: later
assignee: Oddur Sigurdsson
claimed: 2026-11-02
depends_on:
- 30
created: 2026-10-20
updated: 2026-11-02
priority: p3
effort: m
area: system
---

## Problem

A file you know is in some archive can't be found by name.

## Proposal

A Spotlight importer that indexes entry names from ZipCatalog.

## Acceptance criteria

- [ ] Searching a name that exists only inside a ZIP finds the archive

## 2026-11-02

2026-11-02: the extension build path is settled (0030's answer); a Spotlight importer is a third .appex in PlugIns, built the same way.

## 2026-11-02

2026-11-02, draft PR. Findings: macOS's own Archives.mdimporter already indexes the names inside ZIPs (mdimport -t shows it, with the file name as text content), so this item's criterion already holds for ZIP without Zipboy. RAR, 7z, and tar.gz get no importer at all, which is where Zipboy's adds something. Built a CSImportExtension (ZipboySpotlight, a third appex, same build path as the Quick Look ones); mdbulkimport discovers it (com.apple.extensionkit log), but a real mdimport of a RAR in ~ didn't launch it and kMDItemDescription stayed empty, and mdimport -t only exercises legacy .mdimporter plug-ins. Not merged: an importer runs on every matching file on the Mac, so it waits until it has been seen indexing. Next step: check whether the app must be in /Applications and launched once, and whether CSImportExtension needs the app's own group/registration.
