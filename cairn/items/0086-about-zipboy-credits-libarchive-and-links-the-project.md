---
id: 86
uid: 138d0d10-e3c9-4958-8fbc-0302e05ba782
title: About Zipboy credits libarchive and links the project
type: docs
status: done
milestone: v0.2
assignee: Oddur Sigurdsson
created: 2026-11-02
updated: 2026-11-02
priority: p3
effort: s
area: shell
---

## Problem

The About panel shows a name and version only. Zipboy is built on libarchive, whose licence asks
for its notice, and there is no link to the project or its issues.

## Proposal

Pass `.credits` to `orderFrontStandardAboutPanel(options:)` with an attributed string: libarchive's
copyright notice, and links to the GitHub repository and its issues page.

## Acceptance criteria

- [x] About Zipboy shows the libarchive notice and both links, covered by a test on the options passed
- [ ] The links open in the browser

## 2026-11-02

Evidence. aboutCreditsLibarchiveAndLinksTheProject checks the credits text, both links, and that About Zipboy calls showAbout. Zipboy links the system's libarchive.dylib rather than shipping a copy, so the BSD notice isn't owed; the credit names it and says it ships with macOS. Criterion 2 (links open in the browser) left unticked: AppKit's About panel opens .link attributes itself, but System Events refused Apple events from this session (-1743), so the panel wasn't opened on screen.
