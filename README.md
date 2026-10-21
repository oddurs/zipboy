<p align="center"><img src="docs/icon.png" width="128" alt=""></p>

# Zipboy

Archives, without the ceremony. Open a ZIP, RAR, 7z, or tarball and it reads like a Finder window:
look inside, preview anything, drag files in and out. There's no Save step. Your changes are kept
as you go.

- **Look inside.** A Finder-style list with thumbnails, search, and a live preview beside it. Press
  Space for Quick Look.
- **Change anything.** Drop files onto any folder, paste, rename in place, make folders, move things
  around, delete. Every change can be undone, and each one saves itself, with versions to go back to.
- **Edit in place.** Double-click a file to open it in its app. Save it there and the archive keeps
  the change.
- **Take things out.** Drag items to Finder, or click Extract to unpack next to the archive. A
  single folder comes out as itself, never a folder inside a folder.
- **Make a zip.** Drop files or folders on the Dock icon, or start a New Archive and drag them in.
- **RAR, 7z, and tar** open as a new ZIP named after the original. The original is never changed.
- **Passwords.** Protected ZIPs ask once. Set Password… in the File menu encrypts with AES-256.

Reading and writing go through the libarchive that ships with macOS, so there are no dependencies.
Entries that would land outside the archive, through `..`, absolute paths, or symlinks, are
skipped. `__MACOSX`, `._*`, and `.DS_Store` are left out both ways.

## Build

Requires macOS 14 and Swift 6 (Command Line Tools are enough).

```sh
scripts/task build      # build/Zipboy.app, universal, ad hoc signed
scripts/task check      # format check, lint, tests, build
```
