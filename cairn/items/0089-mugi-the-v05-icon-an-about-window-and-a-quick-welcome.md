---
id: 89
uid: 3956ef63-00ec-4672-b02e-5a40c61f82ad
title: 'Mugi: the V05 icon, an About window, and a quick welcome'
type: feature
status: done
milestone: v0.1
assignee: Oddur Sigurdsson
created: 2026-11-02
updated: 2026-11-02
priority: p1
effort: m
area: shell
---

## Problem

Zipboy's identity is now Mugi, a cream mochi bear with an apricot zippered pouch, designed in Mugi
Atelier, where V05 was approved as the app icon. The app still ships the earlier running-boy icon,
its About panel is the bare standard one, and a first launch says nothing about how the app works.

## Proposal

- The V05 icon, light and dark, generated from the designer's 1024 px renders into the macOS icon
  grid by `scripts/make-icon.swift`. A Finder icon with a dark variant needs Xcode's `actool`, which
  Command Line Tools lack, so the running app swaps its own icon (Dock, About, alerts) to the dark
  rendering in Dark Mode.
- An About window with Mugi ("The original" pose), the version, a line on what Zipboy is, the
  libarchive credit, and the project links.
- A three-page welcome on first launch, each page with the pose the Mugi system assigns to that use:
  "Hello there" to introduce, "This way" to show how it works, "Nicely done" to finish. Skippable,
  shown once, and back from Help > Welcome to Zipboy.

## Acceptance criteria

- [x] `swift scripts/make-icon.swift` writes the light and dark icons from the V05 renders, and the built app carries both
- [x] In Dark Mode the running app's icon is the dark rendering, and in Light Mode the light one, switching live
- [x] About Zipboy shows Mugi, the version, the libarchive credit, and both links, in either appearance
- [x] The welcome shows once on first launch, can be skipped from any page, and Help > Welcome to Zipboy brings it back
- [x] Mugi sits on a soft contact shadow in both appearances, checked by rendering each view in light and dark

## 2026-11-02

Evidence. make-icon.swift places the V05 renders (approved mugi-v05.png, and the designer's dark rendering of the same zipboy-mugi-centered-v5 project) on the 824-in-1024 grid the designer's own .icns uses; the built app carries AppIcon.icns, AppIconDark.icns, and Resources/Mugi. theRunningAppSwitchesItsIconWithTheAppearance flips NSApp.appearance and checks the icon's backdrop goes dark and back. About and each welcome page were rendered offscreen in Aqua and Dark Aqua and looked at: Mugi stands on a contact shadow (checked by pixels in mugiStandsOnAShadowInBothAppearances), text uses system colours, nothing clips. Poses follow the Mugi manifest's uses: neutral for About, welcome / presenting / celebrate for the three pages. Limits: Finder shows only the light icon (a dark Finder icon needs actool, i.e. Xcode); the accent-tinted Continue renders grey offscreen because an offscreen window isn't key; windows were not seen on a real screen this session.
