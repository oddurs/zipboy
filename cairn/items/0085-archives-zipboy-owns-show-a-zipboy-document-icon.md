---
id: 85
uid: f3bf3c8b-5f15-4245-ae53-87e102799cc2
title: Archives Zipboy owns show a Zipboy document icon
type: feature
status: planned
milestone: v0.4
created: 2026-11-02
updated: 2026-11-02
priority: p3
effort: s
area: distribution
---

## Problem

Once Zipboy is the default for ZIPs, Finder still draws Archive Utility's generic zipper page, so
nothing says which app will open them.

## Proposal

Render a document icon in `scripts/make-icon.swift`: the system's page shape with a small Zipboy
mark and the format name, written to `Resources/ArchiveDocument.icns`. Reference it with
`CFBundleTypeIconFile` on the document types Zipboy is the owner of, not on ones it only views.

## Acceptance criteria

- [x] `swift scripts/make-icon.swift` writes the document icon, and `BundleTests` checks every owned type names it
- [ ] With Zipboy as the default for ZIP, Finder shows the new icon after `lsregister -f`, checked on screen

## 2026-11-02

2026-11-02: done the native way instead of drawing a page: CFBundleTypeIconSystemGenerated on the ZIP type (the one Zipboy writes), so macOS composes the Mugi app icon onto a document page with the extension. No document art to maintain, and it follows the icon. zipsZipboyOwnsGetADocumentIconMadeFromMugi checks only the Editor type carries it. Criterion 1 is met in that spirit (BundleTests checks it) though make-icon.swift no longer needs to draw anything; criterion 2 not checked on screen: it needs Zipboy set as the default for ZIPs, which I won't change on this Mac unasked, and Screen Recording is off.
