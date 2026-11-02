# Using Zipboy with VoiceOver and the keyboard

A checklist to run by hand with VoiceOver (⌘F5) and Full Keyboard Access (System Settings > Keyboard >
Keyboard navigation) turned on. `AccessibilityTests` checks what code can: every control VoiceOver
reaches has a name, list rows carry name, kind, and size, and adding, deleting, and saving are
announced. What it can't check is how it sounds and whether every step can be done without a mouse.
Tick each line on a real Mac, and note the macOS version.

## First launch

- [ ] The welcome reads its heading and text; Mugi is described; "Page 1 of 3" is read
- [ ] Return goes on, Escape skips, the arrow keys turn the pages

## Opening and browsing

- [ ] ⌘O, choose an archive: the window title and subtitle (items, size) are read
- [ ] Tab reaches the list; arrows move through rows; each row reads name, date, size, and kind
- [ ] Right and Left open and close folders; typing a name jumps to it
- [ ] Space opens Quick Look on the selection, and Space or Escape closes it

## The inspector

- [ ] Tab reaches the inspector: the name, kind, and each table row ("Size: 2 KB") are read
- [ ] Its two buttons are reached and named, and the prominent one acts on Space

## Changing the archive

- [ ] ⇧⌘A, choose files: "Added 2 items" is announced and the new items are selected
- [ ] Return renames; Escape puts the old name back
- [ ] ⌘⌫ deletes: "Deleted “name”" is announced; ⌘Z brings it back
- [ ] ⌘S on an untitled archive, then save: "Saved" is announced

## Extracting, searching, and long work

- [ ] ⌘E extracts; ⌥⌘E asks where, in a panel VoiceOver reads
- [ ] ⌘F reaches the search field; a search with no results reads "No Results for …"
- [ ] During a long add or extract, the strip under the toolbar is reached; its Stop button is named,
  and Escape stops the work

## Elsewhere

- [ ] Settings: every checkbox and pop-up is read with its label, in tab order
- [ ] About Zipboy: Mugi is described, and both links are reached and open
- [ ] The Accessibility Inspector's audit (Xcode > Open Developer Tool) reports no issues
