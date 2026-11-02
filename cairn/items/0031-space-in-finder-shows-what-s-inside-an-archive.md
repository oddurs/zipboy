---
id: 31
uid: d3ca95f9-8e89-4a00-bf83-90834ffd1855
title: Space in Finder shows what's inside an archive
type: feature
status: backlog
milestone: v0.4
depends_on:
- 30
created: 2026-10-20
updated: 2026-11-02
priority: p0
effort: l
area: system
---

## Problem

Pressing Space on a ZIP in Finder shows a generic icon. Seeing inside means opening an app.

## Proposal

A Quick Look preview extension that lists the archive's contents as a compact tree with sizes, using ZipCatalog for ZIPs and libarchive's listing for the rest, without unpacking anything.

## Acceptance criteria

- [ ] Space on a ZIP, RAR, 7z, or tarball in Finder shows its tree within 300 ms for 10,000 entries
- [x] Encrypted archives show their names when the format allows, and a lock otherwise
- [ ] The extension ships inside the notarized app and registers on first launch

## 2026-11-02

2026-11-02: built in the same PR as the 0030 spike. Measured in the release build's extension through Quick Look (QLPreviewView in another process, timing from the extension's own log): 10,000 entries listed and rendered in 66 ms; RAR5, 7z, tar.gz, and a RAR with encrypted names (shown as hidden) all preview, and a plain .gz falls back to the icon. Criterion 2: ZIP names show with a lock when entries are encrypted; RAR/7z with encrypted headers say the names are encrypted (ArchivePreviewTests). Criterion 1 left unticked: the page was never seen in Finder on screen, because this session lost Screen Recording and Automation permission; WebKit's layout time for the page is not in the 66 ms. Criterion 3 waits on 0058 for notarization; Launch Services registers the extension when the app is registered, as on first launch from /Applications.
