import CoreSpotlight
import Foundation

/// What Spotlight learns about an archive from its listing.
public enum Spotlight {
    /// More entries than this is a huge archive; its first ones are still worth finding.
    public static let entryLimit = 20_000

    /// The entry names become the archive's text, one per line, so a search for any of them finds it;
    /// the summary says how many items it holds.
    public static func describe(_ listing: ArchiveListing, into attributes: CSSearchableItemAttributeSet) {
        guard !listing.namesHidden else { return }
        let names = listing.entries.map { ($0.path as NSString).lastPathComponent }
        attributes.textContent = names.joined(separator: "\n")
        let files = listing.entries.filter { !$0.isDirectory }.count
        attributes.contentDescription =
            "\(listing.format) archive, \(files == 1 ? "1 file" : "\(files.formatted()) files")"
    }
}
