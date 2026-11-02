---
paths:
  - "Sources/Zipboy/**"
---

# The look

- Neon green is the one brand colour; everything else is native. Colours, spacing, radii, and type come
  from `Theme` (`Theme.neon`, `.accent`, `.ink`, `Theme.Space`, `Theme.Radius`, `Theme.Font`). No colour
  literals or one-off sizes in views.
- `Theme.neon` is a fill; text and symbols on it use `Theme.ink`, never white. Anything that must read
  against the window (strokes, glyphs, text) uses `Theme.accent`, which deepens in light mode.
- Native controls get the green through the app accent (`Theme.registerAccent`), set only while the
  person uses Multicolor. Don't tint system controls by hand.
- A view has at most one prominent action (`ActionButton(prominent: true)`). Rename, delete, and the
  rest live in menus and the keyboard, not as more buttons.
- Layers can't follow appearance changes: resolve colours with `Theme.cgColor(_:in:)` in `updateLayer`
  or `viewDidLayout`. System fills (`tertiarySystemFill` and friends) resolve opaque in a layer; use
  `Theme.quiet` or `Theme.well`.
- `NSStackView`'s `.width` alignment only matches arranged views to each other. Pin widths to the stack.
- `LookTests` holds the contrast checks; a new colour pairing gets one there.
