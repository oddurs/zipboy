---
id: 92
uid: 1b7d4736-e418-47e8-9416-c42843e87cff
title: Which split archives can libarchive join?
type: spike
status: done
milestone: v0.4
assignee: Oddur Sigurdsson
created: 2026-11-06
updated: 2026-11-07
closed_at: 2026-11-07
priority: p1
effort: s
area: archive
---

## Question

`archive_read_open_filenames` reads several files as one stream. Does the libarchive that ships with
macOS read each common kind of split archive through it: `.part1.rar`, `.r00`, `.z01` with `.zip`,
`.7z.001`, and plain `.001` pieces? Which need Zipboy to join the pieces itself first?

## Why it matters

Zipboy opens one file at a time, so opening part of a split archive fails or shows only that part.
The answer sets the size of the item that depends on this one.

## Timebox

Half a day. The leading guess: multi-volume RAR works through `archive_read_open_filenames`, and plain
`.001` pieces only need concatenating; split ZIP is the unknown, since its central directory is in the
last piece.

## Answer

Tested empirically against macOS's system `/usr/lib/libarchive.2.dylib` (`libarchive 3.7.4`, linked by `CArchive`) and `libarchive 3.8.11` using `archive_read_open_filenames(a, filenames, 65536)` with `Archive.configureReader`'s filter and format registrations:

| Split archive kind | Volume order passed to `archive_read_open_filenames` | `archive_read_open_filenames` result on macOS `libarchive.2.dylib` | Needs Zipboy to join pieces first? |
| --- | --- | --- | --- |
| `.part1.rar`, `.part2.rar`, … (RAR4 & RAR5) | `[name.part1.rar, name.part2.rar, …]` | **Reads directly.** Both `rar` and `rar5` readers switch volumes on `LHD_SPLIT_AFTER` / `SPLIT_AFTER` and `EARC_NEXT_VOLUME`. | **No** (and cannot be byte-concatenated: each volume has its own `Rar!` signature, archive header, split file header, and end block). |
| `.rar`, `.r00`, `.r01`, … (RAR4 & RAR5) | `[name.rar, name.r00, name.r01, …]` | **Reads directly.** `archive_read_open_filenames` does not inspect extensions; it walks the caller-supplied `filenames` array in order. | **No** (same framed multi-volume RAR format as `.partN.rar`). |
| `.z01`, `.z02`, …, `.zip` (PKWARE split ZIP) | `[name.z01, name.z02, …, name.zip]` | **Reads directly.** `archive_read_open_filenames` supplies a volume-switch callback, so libarchive's streaming ZIP reader skips the 4-byte `PK\x07\x08` (`0x08074b50`) split marker at the start of `.z01` and streams local file headers across volume boundaries. | **No** when opened read-only through libarchive (`0093` opens split archives read-only as imports). Note that `ZipCatalog` cannot read `.z01`+`.zip` directly because Central Directory offsets in `.zip` are relative to each entry's `diskNumberStart`. |
| `.7z.001`, `.7z.002`, … (`7zz a -v…`) | `[name.7z.001, name.7z.002, …]` | **Reads directly** across any chunk size (`4 KB`, `20 KB`, `32 KB`, etc.). `archive_read_open_filenames` registers cross-volume `client_seek_proxy` + `file_switch`, allowing the 7z reader to seek from the 32-byte header in `.7z.001` to the `NextHeader` at the end of the final piece and back. | **No.** |
| Plain `.001`, `.002`, … (`.tar.001`, `.tar.bz2.001`, `.tar.gz.001`, `.zip.001`, etc.) | `[name.001, name.002, …]` | **Partial.** `.zip.001`, `.tar.gz.001`, and `.tar.xz.001` succeed, but **`.tar.001` and `.tar.bz2.001` fail whenever the piece size is not a multiple of 512 bytes** (e.g. `20,000`-byte pieces fail with `Damaged tar archive` / `Truncated tar archive` because `archive_read_open_filenames` returns a short read at the volume boundary instead of coalescing across `file_switch`). | **Yes for non-`.7z.001` plain `.001` chains** (or stream-concatenate plain `.001` pieces into a temporary staging file before calling `archive_read_open_filename`, which guarantees 512-byte block alignment for `.tar.001` and `.tar.bz2.001`). |

### Implementation plan for `0093`

1. **CArchive declaration**:
   - Add `int archive_read_open_filenames(struct archive *, const char **, size_t);` to `Sources/CArchive/shim.h`.
2. **Volume discovery and missing-piece check** (given any piece URL):
   - **`.part<N>.rar`** (including zero-padded `.part01.rar`): collect `<stem>.part<k>.rar` in the same directory, require contiguous `1…max` (and if only `.part1.rar` is present, report `<stem>.part2.rar` missing when the volume header/end-block indicates a multi-volume set).
   - **`.rar` + `.r00`, `.r01`, …**: when opening `.r<NN>` (or a `.rar` alongside `.r00`), order `[<stem>.rar, <stem>.r00, <stem>.r01, …]` and verify `<stem>.rar` and every `00…max` exist without gaps.
   - **`.z01`, `.z02`, …, `.zip`**: when opening `.z<NN>` (or a `.zip` that has a sibling `.z01` or starts with `PK\x07\x08` / has `diskNumber > 0` in its EOCD), order `[<stem>.z01, <stem>.z02, …, <stem>.zip]` and verify `<stem>.zip` and every `01…max` exist without gaps.
   - **`.7z.001`, `.7z.002`, … and plain `.001`, `.002`, …**: order `[<stem>.001, <stem>.002, …, <stem>.<max>]`, require `.001` and at least `.002` with no gaps in `1…max`.
   - Any gap throws a typed `ArchiveError` naming the first missing piece (e.g. `archive.part2.rar` or `split.z01`).
3. **Reading path**:
   - Pass `.partN.rar`, `.rar`+`.rNN`, `.z01`+`.zip`, and `.7z.001` volume arrays directly to `archive_read_open_filenames`.
   - For plain `.001` chains (other than `.7z.001`), concatenate the pieces into a temporary file under the workspace/staging directory (after checking free space) and open with `archive_read_open_filename`, so `.tar.001` and `.tar.bz2.001` with non-512-aligned piece sizes never hit short reads at volume boundaries.
   - Open all split archives as read-only imports (`importedFrom` set, `fileURL = nil`) so autosave cannot overwrite any piece.

## Result

macOS libarchive.2.dylib reads .part1.rar, .rar+.r00, .z01+.zip, and .7z.001 directly via archive_read_open_filenames; plain .001 chains (.tar.001, .tar.bz2.001) fail on non-512-byte chunk boundaries and should be concatenated to a staging file first.
