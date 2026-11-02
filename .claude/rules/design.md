---
paths:
  - "Sources/Zipboy/**"
---

# The look

- Zipboy looks like macOS: the person's accent colour, the system selection, stock controls, SF Pro. No
  brand colour, no custom row views or button drawing, and nothing that overrides the person's
  appearance or accent settings.
- Spacing, radii, and type come from `Theme` (`Theme.Space`, `Theme.Radius`, `Theme.Font`). No one-off
  sizes in views. Colour is semantic system colour (`.controlAccentColor`, `.secondaryLabelColor`,
  `.separatorColor`), plus `Theme.well` and `Theme.quiet` for the few neutral surfaces.
- A view has at most one prominent action (`NSButton.push(_:action:prominent: true)`), tinted with the
  accent but with no Return key, since Return renames in the list. Rename, delete, and the rest live in
  menus and the keyboard, not as more buttons.
- Empty states follow the system's content-unavailable layout: a symbol, a heading, a line of help, at
  most one button.
- Drop feedback is the accent colour, and only where the drop would be accepted.
- Layers can't follow appearance changes: resolve colours with `Theme.cgColor(_:in:)` in `updateLayer`
  or `viewDidLayout`. System fills (`tertiarySystemFill` and friends) resolve opaque in a layer; use
  `Theme.quiet` or `Theme.well`.
- `NSStackView`'s `.width` alignment only matches arranged views to each other. Pin widths to the stack.
