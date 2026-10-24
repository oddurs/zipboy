// Prints "<window id> <x> <y> <width> <height> <title>" for each on-screen window of an app.
// Usage: winid <app name>
import CoreGraphics

let owner = CommandLine.arguments.dropFirst().first ?? "Zipboy"
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows
where window[kCGWindowOwnerName as String] as? String == owner && window[kCGWindowLayer as String] as? Int == 0 {
    let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let parts = ["X", "Y", "Width", "Height"].map { "\(bounds[$0] ?? 0)" }
    print(window[kCGWindowNumber as String] ?? 0, parts.joined(separator: " "), window[kCGWindowName as String] ?? "")
}
