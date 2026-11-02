import CoreSpotlight
import ZipboyKit

/// Spotlight's importer for archives: it records the names inside, so searching for a file that exists
/// only inside a ZIP finds the archive. It reads the listing, never the contents.
@objc(ZipboyImportProvider)
final class ImportProvider: CSImportExtension {
    override func update(_ attributes: CSSearchableItemAttributeSet, forFileAt contentURL: URL) throws {
        let listing = try Archive.list(contentURL, limit: Spotlight.entryLimit)
        Spotlight.describe(listing, into: attributes)
    }
}
