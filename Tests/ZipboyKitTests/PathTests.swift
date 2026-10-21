import Testing
import ZipboyKit

@Suite struct EntryPathTests {
    @Test func keepsOrdinaryPaths() {
        #expect(EntryPath.sanitized("docs/read me.txt") == "docs/read me.txt")
        #expect(EntryPath.sanitized("./a/./b/") == "a/b")
        #expect(EntryPath.sanitized("win\\style\\path.txt") == "win/style/path.txt")
    }

    @Test func rootsAbsolutePathsInsideTheArchive() {
        #expect(EntryPath.sanitized("/etc/passwd") == "etc/passwd")
    }

    @Test func refusesToClimbOut() {
        #expect(EntryPath.sanitized("../evil") == nil)
        #expect(EntryPath.sanitized("a/../../evil") == nil)
        #expect(EntryPath.sanitized("a\\..\\..\\evil") == nil)
        #expect(EntryPath.sanitized("") == nil)
        #expect(EntryPath.sanitized("./") == nil)
    }

    @Test func dropsFinderMetadata() {
        #expect(EntryPath.sanitized("__MACOSX/a/._b.txt") == nil)
        #expect(EntryPath.sanitized("a/.DS_Store") == nil)
        #expect(EntryPath.sanitized("a/._b.txt") == nil)
        #expect(EntryPath.sanitized("a/.hidden") == "a/.hidden")
    }

    @Test func allowsLinksThatStayInside() {
        #expect(EntryPath.linkStaysInside(path: "App/Current", target: "Versions/A"))
        #expect(EntryPath.linkStaysInside(path: "a/b/link", target: "../../c"))
    }

    @Test func refusesLinksThatLeave() {
        #expect(!EntryPath.linkStaysInside(path: "link", target: "/etc"))
        #expect(!EntryPath.linkStaysInside(path: "link", target: ".."))
        #expect(!EntryPath.linkStaysInside(path: "a/link", target: "../../x"))
    }
}

@Suite struct NamingTests {
    @Test func keepsAFreeName() {
        #expect(Naming.unique("a.txt", isDirectory: false, taken: ["b.txt"]) == "a.txt")
    }

    @Test func numbersLikeFinder() {
        #expect(Naming.unique("photo.jpg", isDirectory: false, taken: ["photo.jpg"]) == "photo 2.jpg")
        #expect(Naming.unique("photo.jpg", isDirectory: false, taken: ["photo.jpg", "photo 2.jpg"]) == "photo 3.jpg")
        #expect(Naming.unique("photo 2.jpg", isDirectory: false, taken: ["photo 2.jpg"]) == "photo 3.jpg")
    }

    @Test func ignoresCaseAsAPFSDoes() {
        #expect(Naming.unique("A.txt", isDirectory: false, taken: ["a.txt"]) == "A 2.txt")
    }

    @Test func numbersFoldersWithoutSplittingAnExtension() {
        #expect(Naming.unique("v1.2", isDirectory: true, taken: ["v1.2"]) == "v1.2 2")
        #expect(Naming.unique("Makefile", isDirectory: false, taken: ["Makefile"]) == "Makefile 2")
    }
}

@Suite struct ZipMethodTests {
    @Test func storesWhatIsAlreadyCompressed() {
        #expect(ZipMethod.forFile(named: "IMG_0001.JPG") == .store)
        #expect(ZipMethod.forFile(named: "inner.zip") == .store)
        #expect(ZipMethod.forFile(named: "notes.txt") == .deflate)
        #expect(ZipMethod.forFile(named: "README") == .deflate)
    }
}
