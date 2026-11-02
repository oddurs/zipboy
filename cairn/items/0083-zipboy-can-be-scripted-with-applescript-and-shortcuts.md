---
id: 83
uid: 904bb285-8b1a-4b71-bd50-9b85a6e50987
title: Zipboy can be scripted with AppleScript and Shortcuts
type: feature
status: planned
milestone: v0.4
created: 2026-11-02
updated: 2026-11-02
priority: p2
effort: m
area: system
---

## Problem

Nothing outside the app can drive it: no AppleScript dictionary, no Shortcuts actions.

## Proposal

App Intents would be the modern route, but its metadata is produced by Xcode's
`appintentsmetadataprocessor`, which Command Line Tools lack, so Shortcuts would not see the
intents. Instead, add a scripting dictionary (`Resources/Zipboy.sdef`, `NSAppleScriptEnabled`,
`OSAScriptingDefinition`) with the Standard Suite for documents plus two commands:
`extract <archive> to <folder>` and `make archive at <file> with files <list>`. Shortcuts can call
them through Run AppleScript. Revisit App Intents if the build ever gains Xcode.

## Acceptance criteria

- [x] `osascript -e 'tell application "Zipboy" to extract POSIX file "/tmp/a.zip" to POSIX file "/tmp/out"'` extracts, covered by a test that runs the command handler directly
- [x] `make archive` writes a ZIP holding the given files
- [ ] Script Editor's Open Dictionary shows both commands with descriptions
- [x] A bad path fails with an AppleScript error naming the path, not a crash

## 2026-11-02

2026-11-02. Commands are extract <archive> [to <folder>] and compress <files> [into <folder>], not make archive at …: make is the standard suite's object-creation command, and these two read as plainly as the Finder services they reuse (AppDelegate.extractArchives / compressFiles). Each suspends the Apple event and works off the main thread. ScriptingTests: round trip, a missing path gives -43 naming the path, one file or a list. BundleTests ties the sdef's cocoa classes to their @objc names and checks the build copies it; xmllint --xinclude validates it. Criterion 3 (Script Editor's dictionary) not checked on screen this session.
