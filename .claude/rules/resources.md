# The icon

The icon is Mugi V05, designed in Mugi Atelier (`~/Code/macos-icon-designer`, `public/mugi/approved`).
Its 1024 px renders, light and dark, are `Resources/Icon/mugi-v05-{light,dark}.png`.
`swift scripts/make-icon.swift` places them on the macOS icon grid and writes `Resources/AppIcon.icns`,
`Resources/AppIconDark.icns`, and `docs/icon.png`. Change the renders in the designer and run it;
never edit the `.icns` files.

Finder shows only the light icon: a dark Finder icon needs an asset catalog, which only Xcode's `actool`
compiles. The running app switches its own icon to the dark one in Dark Mode (`Mugi.appIcon`).
