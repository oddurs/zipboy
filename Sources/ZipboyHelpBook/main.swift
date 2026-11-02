import Foundation
import ZipboyKit

// Writes Zipboy's Apple Help Book from HelpTopics. scripts/task build runs it, then indexes the
// pages with hiutil. Usage: ZipboyHelpBook <path/to/Zipboy.help> <version>

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: ZipboyHelpBook <Zipboy.help> <version>\n".utf8))
    exit(2)
}
let book = URL(fileURLWithPath: arguments[1])
let pages = book.appendingPathComponent("Contents/Resources/en.lproj")
try? FileManager.default.removeItem(at: book)
try FileManager.default.createDirectory(at: pages, withIntermediateDirectories: true)
let info = try PropertyListSerialization.data(
    fromPropertyList: HelpTopics.bookInfo(version: arguments[2]), format: .xml, options: 0)
try info.write(to: book.appendingPathComponent("Contents/Info.plist"))
try Data(HelpTopics.index().utf8).write(to: pages.appendingPathComponent("index.html"))
for topic in HelpTopics.all {
    try Data(HelpTopics.page(for: topic).utf8).write(to: pages.appendingPathComponent("\(topic.anchor).html"))
}
print("wrote \(book.path) with \(HelpTopics.all.count) topics")
