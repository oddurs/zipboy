---
id: 64
uid: 823a4a4f-a6c8-4e44-96f6-9752467567b5
title: Add Settings window and sensible defaults
type: feature
status: done
milestone: v0.2
assignee: Oddur Sigurdsson
created: 2026-11-01
updated: 2026-11-01
closed_at: 2026-11-01
priority: p1
effort: m
area: shell
---

## Problem

Zipboy has no Settings window (`⌘,`) or user-configurable defaults for launch behavior, browsing (folders on top, auto-expanding single-folder archives, showing dotfiles), extraction destination/folder wrapping, compression level, or making Zipboy the default archive handler.

## Proposal

- Add `Settings` in `Sources/ZipboyKit/Settings.swift` backed by `UserDefaults` with registered sensible defaults, live change notifications, and `resetToDefaults()`.
- Wire `CompressionLevel` (`fast`, `balanced`, `best`) into `Archive.writeZip` via libarchive's `zip:compression-level` option.
- Wire `keepFoldersOnTop` and `showHiddenFiles` into `Node` and `BrowserViewController` (plus `View > Show Hidden Files` with `⌘⇧.`).
- Wire `extractDestination`, `wrapBehavior`, and `revealInFinder` into `BrowserViewController.extract`.
- Build a native macOS `SettingsWindowController` (`⌘,` in `MainMenu`) using standard `NSGridView` form sections, default-app controls, and a `Restore Defaults` button.

## Acceptance criteria

- [x] `Settings` registers sensible defaults out of the box and persists changes across reads and `resetToDefaults()`
- [x] `Archive.writeZip` honors `CompressionLevel` (`fast`, `balanced`, `best`)
- [x] `Node` sorting and filtering honor `keepFoldersOnTop` and `showHiddenFiles`
- [x] `MainMenu` includes `Settings…` (`⌘,`) and `Show Hidden Files` (`⌘⇧.`), and `SettingsWindowController` updates controls when defaults are restored

## 2026-11-01

Added Settings in Sources/ZipboyKit/Settings.swift and SettingsWindowController in Sources/Zipboy/SettingsWindowController.swift; wired CompressionLevel into Archive.writeZip, keepFoldersOnTop/showHiddenFiles/autoExpandSingleFolder into Node and BrowserViewController, and extractDestination/wrapExtractedFiles/revealExtractedInFinder into extraction; added Settings… (⌘,) and Show Hidden Files (⌘⇧.) to MainMenu.

## Result

Zipboy now includes a native macOS Settings window (⌘,) with sensible defaults for launch behavior, folder-first sorting, single-folder auto-expansion, hidden file visibility (⌘⇧.), extraction destination/folder wrapping, Deflate compression level, default app registration, and one-click Restore Defaults.
