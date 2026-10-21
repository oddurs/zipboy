import Foundation

/// One file or folder in an unpacked archive. Nodes are classes because the outline view tells items
/// apart by identity.
public final class Node {
    public let url: URL
    /// Slash-separated, from the archive's root.
    public let path: String
    public let isDirectory: Bool
    public let isSymlink: Bool
    /// For a folder, everything inside it added up.
    public private(set) var size: Int64
    public let modified: Date?
    public private(set) var children: [Node] = []
    public private(set) weak var parent: Node?

    init(url: URL, path: String, isDirectory: Bool, isSymlink: Bool, size: Int64, modified: Date?) {
        self.url = url
        self.path = path
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.size = size
        self.modified = modified
    }

    public var name: String { url.lastPathComponent }

    /// Files and folders below this one, not counting itself.
    public var descendantCount: Int { children.reduce(children.count) { $0 + $1.descendantCount } }

    /// Reads the tree under `root`. The root node itself stands for the archive.
    public static func scan(_ root: URL) -> Node {
        let node = Node(url: root, path: "", isDirectory: true, isSymlink: false, size: 0, modified: nil)
        node.load()
        return node
    }

    private func load() {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        let urls =
            (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys)) ?? []
        children = urls.filter { !EntryPath.isJunk($0.lastPathComponent) }.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isSymlink = values?.isSymbolicLink == true
            let child = Node(
                url: url,
                path: path.isEmpty ? url.lastPathComponent : "\(path)/\(url.lastPathComponent)",
                isDirectory: values?.isDirectory == true && !isSymlink,
                isSymlink: isSymlink,
                size: Int64(values?.fileSize ?? 0),
                modified: values?.contentModificationDate)
            child.parent = self
            if child.isDirectory { child.load() }
            return child
        }
        if isDirectory { size = children.reduce(0) { $0 + $1.size } }
    }

    /// The node at a slash-separated path, if it is still there.
    public func find(_ path: String) -> Node? {
        guard !path.isEmpty else { return self }
        var node = self
        for part in path.split(separator: "/") {
            guard let next = node.children.first(where: { $0.name == part }) else { return nil }
            node = next
        }
        return node
    }

    /// A copy holding only the nodes whose names contain `query`, with the folders that lead to them.
    /// Nil when nothing matches.
    public func filtered(_ query: String) -> Node? {
        let kept = children.compactMap { $0.filtered(query) }
        let matches = !path.isEmpty && name.localizedStandardContains(query)
        guard matches || !kept.isEmpty || path.isEmpty else { return nil }
        let copy = Node(
            url: url, path: path, isDirectory: isDirectory, isSymlink: isSymlink, size: size, modified: modified)
        // A matching folder keeps all of its contents, so a search can narrow to a folder and browse it.
        copy.children = matches ? children.map { $0.copied() } : kept
        copy.children.forEach { $0.parent = copy }
        return copy
    }

    private func copied() -> Node {
        let copy = Node(
            url: url, path: path, isDirectory: isDirectory, isSymlink: isSymlink, size: size, modified: modified)
        copy.children = children.map { $0.copied() }
        copy.children.forEach { $0.parent = copy }
        return copy
    }

    /// Orders children, folders and files mixed as Finder does, by the given key.
    public func sort(by key: SortKey, ascending: Bool) {
        children.sort { a, b in
            let order: ComparisonResult
            switch key {
            case .name: order = a.name.localizedStandardCompare(b.name)
            case .size:
                order = a.size == b.size ? .orderedSame : (a.size < b.size ? .orderedAscending : .orderedDescending)
            case .modified:
                let x = a.modified ?? .distantPast, y = b.modified ?? .distantPast
                order = x == y ? .orderedSame : (x < y ? .orderedAscending : .orderedDescending)
            case .kind: order = a.kind.localizedStandardCompare(b.kind)
            }
            if order == .orderedSame { return a.name.localizedStandardCompare(b.name) == .orderedAscending }
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
        children.forEach { $0.sort(by: key, ascending: ascending) }
    }

    /// The localized kind Finder shows, such as "PNG image".
    public var kind: String {
        if isDirectory { return "Folder" }
        if isSymlink { return "Alias" }
        return (try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey]))?.localizedTypeDescription
            ?? "Document"
    }

    public enum SortKey: String, Sendable {
        case name, size, modified, kind
    }
}
