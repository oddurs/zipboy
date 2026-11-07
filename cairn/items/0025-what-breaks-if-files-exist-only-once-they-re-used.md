---
id: 25
uid: c7a8b41b-1179-44d6-afb5-a2b514cc6aab
title: What breaks if files exist only once they're used?
type: spike
status: done
milestone: v0.3
assignee: Oddur Sigurdsson
depends_on:
- 18
created: 2026-10-20
updated: 2026-11-07
closed_at: 2026-11-07
priority: p0
effort: s
area: document
---

## Question

If a ZIP is browsed from its catalog and an entry is unpacked only on first use, what depends on the file being there today? Quick Look, Open With, drag out, copy, folder sizes, the FileWatcher, search, thumbnails, extract. Where does each one need the bytes, and how long can it wait?

## Why it matters

Opening is the first thing anyone does, and today it costs the full unpacked size in time and disk.

## Timebox

One day. The answer lists every touch point with a plan, and confirms solid RAR and 7z stay fully unpacked.

## Answer

Lazy catalog browsing (`0026`) and on-demand materialization (`0027`) apply **only to ZIPs** read via `ZipCatalog`. **Solid RAR, solid 7z, and tarballs stay eagerly unpacked into `Workspace`**: solid blocks and stream-compressed tarballs cannot seek to entry *N* without decompressing everything ahead of it, so lazy extraction there would stall individual previews as badly as opening.

Audit of every touch point in `ZipboyKit` and `Zipboy`:

- **Folder sizes, sort, search, and archive summary (`Node`, `BrowserViewController.reload`, `PreviewViewController.showArchive`) — 0 bytes needed, 0 ms wait.**
  - *Today*: `Node.scan(_:)` walks `workspace.contents` with `FileManager.contentsOfDirectory`.
  - *Plan (`0026`)*: Add `Node.fromCatalog(_:workspaceRoot:)` synthesizing intermediate folder nodes and summing `uncompressedSize` upward into folder `size`. `Node.sort`, `Node.filtered` (search and hidden-file toggle), and `showArchive` already operate purely on in-memory `Node` properties.
- **Row icons, `Node.kind`, and Open With menu (`FileTree.swift`, `BrowserViewController.icon(for:)`, `openWithMenu(for:)`) — 0 bytes needed, 0 ms wait.**
  - *Breaks today*: `NSWorkspace.shared.icon(forFile: url.path)` returns a generic blank page when `url` does not exist on disk, and `NSWorkspace.shared.urlsForApplications(toOpen: url)` returns `[]` for a missing file. `Node.kind` already falls back to `UTType(filenameExtension:)`.
  - *Plan (`0026`)*: When `!fileExists`, resolve icons with `NSWorkspace.shared.icon(for: node.isDirectory ? .folder : (UTType(filenameExtension: ext) ?? .data))` and populate Open With via `urlsForApplications(toOpen: contentType)`.
- **Inline row thumbnails (`BrowserViewController.icon(for:)`) — needs bytes only after materialization; 0 ms on scroll.**
  - *Breaks today*: `QLThumbnailGenerator.Request(fileAt: node.url)` runs for every visible image, movie, or PDF row. Materializing on scroll would violate `0026`'s rule that opening writes nothing under `$TMPDIR/Zipboy` until an entry is used.
  - *Plan (`0026`/`0027`)*: Request `QLThumbnailGenerator` only when `fileExists(atPath: node.url.path)` is already true; unmaterialized rows show their UTType icon until previewed or opened, then refresh in place.
- **Inspector Quick Look, Spacebar `QLPreviewPanel`, and checksums (`PreviewViewController.showItem`, `BrowserViewController`) — needs bytes; < 200 ms budget under 10 MB.**
  - *Breaks today*: `QLPreviewView` and `QLPreviewPanel` receive a missing `NSURL`; `Checksums.compute(for:)` fails; `destinationOfSymbolicLink` returns `nil`; `verbatimEntry` returns `nil` because it `lstat`s the workspace.
  - *Plan (`0027`)*: Render Name, Kind, Size, Modified, symlink target, and catalog `CRC-32` immediately (0 ms) from `ZipCatalog.Entry`. Materialize the selected entry off the main thread (deduplicated per path so concurrent callers unpack once) with a spinner in the preview well, then hand the file URL to `QLPreviewView`/`QLPreviewPanel` and compute `SHA-256`.
- **Open, Open With, and nested archives (`openItems`, `openWith`, `openWithOther`, `openNestedArchive`) — needs bytes; < 200 ms for small files, cancellable `LongTask` progress for large ones.**
  - *Breaks today*: `NSWorkspace.shared.open` and `NSDocumentController.openDocument` fail with file-not-found.
  - *Plan (`0027`)*: Await single-entry materialization into the lazily created `Workspace` before launching Launch Services or opening the child `ArchiveDocument`, stamping `com.apple.quarantine` from the source ZIP.
- **Drag out (`pasteboardWriterForItem`, `NSFilePromiseProvider`) — needs bytes on drop; drag starts in 0 ms.**
  - *Breaks today*: `BrowserViewController` already returns `NSFilePromiseProvider` when `!fileExists`, but `filePromiseProvider(_:writePromiseTo:)` currently writes an empty `Data()` stub for missing files.
  - *Plan (`0027`)*: Fulfil the file promise on its `OperationQueue` by extracting the entry (or folder subtree) directly to the drop `url` and propagating `com.apple.quarantine`.
- **Copy (`Cmd+C`) and Share (`BrowserViewController.copy`) — needs bytes before pasteboard handoff; < 200 ms small, cancellable progress large.**
  - *Breaks today*: `NSPasteboard.general.writeObjects` writes nonexistent workspace `NSURL`s, so pasting in Finder fails.
  - *Plan (`0027`)*: Materialize selected entries/folders into `Workspace` first, then write those materialized `NSURL`s to `NSPasteboard.general`.
- **Extract and Extract To… (`BrowserViewController.extract`, Finder service, AppleScript) — needs bytes during task; streams with progress.**
  - *Breaks today*: `BrowserViewController.extract` reads `FileCopy.size(of: urls)` (`0` when missing) and copies from `node.url` in `Workspace`. (Finder's Extract Here and AppleScript `extract` call `Archive.extract` directly on the archive file and already work unchanged.)
  - *Plan (`0027`)*: Sum `nodes.map(\.size)` for progress; stream unmaterialized entries straight from `sourceZip` to the destination without staging through `$TMPDIR/Zipboy`, copy materialized/edited files from `Workspace`, and stamp `com.apple.quarantine`.
- **`Workspace`, `FileWatcher`, edits, Undo/Redo, and `Save` (`ArchiveDocument`) — 0 bytes needed for catalog-only edits.**
  - *Breaks today*: `Workspace` and `FileWatcher` allocate `$TMPDIR/Zipboy/<uuid>` eagerly on open; `Move.perform()` calls `rename(2)` on disk (`ENOENT` on unmaterialized paths); `buildDeltaPlan` scans `workspaceRoot` on disk and would drop every unmaterialized entry on save.
  - *Plan (`0026`/`0027`)*: Create `Workspace` and `FileWatcher` lazily on first materialization or file addition. Track an in-memory entry overlay (`currentPath -> ZipCatalog.Entry` plus deleted/added paths) so renaming, moving, or deleting unmaterialized entries mutates the overlay and registers an undo closure with zero disk I/O. When an entry materializes into `Workspace`, record `(entry, FileIdentity)` in `trackedByInode` so it still saves `.verbatim` unless `FileWatcher` or `lstat` sees an external edit; `buildDeltaPlan` walks the merged overlay + workspace so untouched unmaterialized entries copy `.verbatim` straight from `sourceZip`.

## Result

Catalog-only browsing applies to ZIPs while solid RAR/7z and tarballs stay eagerly unpacked; every UI, pasteboard, promise, watcher, edit, and delta-save touch point is mapped for 0026 and 0027.
