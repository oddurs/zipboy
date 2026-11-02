import Foundation
import UniformTypeIdentifiers

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
    public private(set) var modified: Date?
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

    /// Builds a `Node` tree directly from a `ZipCatalog` without touching the disk.
    public static func fromCatalog(_ catalog: ZipCatalog, root: URL) -> Node {
        let rootNode = Node(url: root, path: "", isDirectory: true, isSymlink: false, size: 0, modified: nil)
        var folders: [String: Node] = ["": rootNode]

        func ensureFolder(_ path: String) -> Node {
            if let existing = folders[path] { return existing }
            let parentPath = (path as NSString).deletingLastPathComponent
            let parentNode = ensureFolder(parentPath)
            let folderURL = root.appendingPathComponent(path, isDirectory: true)
            let folderNode = Node(
                url: folderURL, path: path, isDirectory: true, isSymlink: false, size: 0, modified: nil)
            folderNode.parent = parentNode
            parentNode.children.append(folderNode)
            folders[path] = folderNode
            return folderNode
        }

        for entry in catalog.entries {
            if entry.isDirectory {
                let folder = ensureFolder(entry.path)
                if let mod = entry.modified { folder.modified = mod }
                continue
            }
            let parentPath = (entry.path as NSString).deletingLastPathComponent
            let parentNode = ensureFolder(parentPath)
            if parentNode.children.contains(where: { $0.path == entry.path }) { continue }
            let itemURL = root.appendingPathComponent(entry.path, isDirectory: false)
            let child = Node(
                url: itemURL,
                path: entry.path,
                isDirectory: false,
                isSymlink: entry.isSymlink,
                size: Int64(entry.uncompressedSize),
                modified: entry.modified
            )
            child.parent = parentNode
            parentNode.children.append(child)
        }

        func computeSizes(_ node: Node) {
            guard node.isDirectory else { return }
            for child in node.children where child.isDirectory {
                computeSizes(child)
            }
            node.size = node.children.reduce(0) { $0 + $1.size }
        }
        computeSizes(rootNode)
        return rootNode
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

    /// A copy holding only the nodes whose names contain `query` (or all nodes when `query` is empty),
    /// with the folders that lead to them, optionally hiding dot-prefixed items. Nil when nothing matches.
    public func filtered(_ query: String, showHiddenFiles: Bool = true) -> Node? {
        if !path.isEmpty, !showHiddenFiles, name.hasPrefix(".") { return nil }
        if query.isEmpty, showHiddenFiles { return self }
        let kept = children.compactMap { $0.filtered(query, showHiddenFiles: showHiddenFiles) }
        if query.isEmpty {
            let copy = Node(
                url: url, path: path, isDirectory: isDirectory, isSymlink: isSymlink, size: size, modified: modified)
            copy.children = kept
            copy.children.forEach { $0.parent = copy }
            return copy
        }
        let matches = !path.isEmpty && name.localizedStandardContains(query)
        guard matches || !kept.isEmpty || path.isEmpty else { return nil }
        let copy = Node(
            url: url, path: path, isDirectory: isDirectory, isSymlink: isSymlink, size: size, modified: modified)
        // A matching folder keeps all of its contents, so a search can narrow to a folder and browse it.
        copy.children = matches ? children.compactMap { $0.copied(showHiddenFiles: showHiddenFiles) } : kept
        copy.children.forEach { $0.parent = copy }
        return copy
    }

    private func copied(showHiddenFiles: Bool = true) -> Node? {
        if !path.isEmpty, !showHiddenFiles, name.hasPrefix(".") { return nil }
        let copy = Node(
            url: url, path: path, isDirectory: isDirectory, isSymlink: isSymlink, size: size, modified: modified)
        copy.children = children.compactMap { $0.copied(showHiddenFiles: showHiddenFiles) }
        copy.children.forEach { $0.parent = copy }
        return copy
    }

    /// Orders children by the given key, optionally keeping folders above files.
    public func sort(by key: SortKey, ascending: Bool, foldersFirst: Bool = false) {
        children.sort { a, b in
            if foldersFirst, a.isDirectory != b.isDirectory {
                return a.isDirectory
            }
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
        children.forEach { $0.sort(by: key, ascending: ascending, foldersFirst: foldersFirst) }
    }

    /// The localized kind Finder shows, such as "PNG image".
    public var kind: String {
        if isDirectory { return "Folder" }
        if isSymlink { return "Alias" }
        if let desc = (try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey]))?.localizedTypeDescription {
            return desc
        }
        if let ext = url.pathExtension.isEmpty ? nil : url.pathExtension,
            let type = UTType(filenameExtension: ext),
            let desc = type.localizedDescription
        {
            return desc
        }
        return "Document"
    }

    public enum SortKey: String, Sendable {
        case name, size, modified, kind
    }
}
