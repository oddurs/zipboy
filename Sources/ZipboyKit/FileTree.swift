import Foundation
import UniformTypeIdentifiers

/// One file or folder in an unpacked archive. Nodes are classes because the outline view tells items
/// apart by identity.
public final class Node {
    private var cachedURL: URL?
    private let workspaceRoot: URL?
    public var url: URL {
        if let cachedURL { return cachedURL }
        let resolved =
            parent?.url.appendingPathComponent(name, isDirectory: isDirectory)
            ?? workspaceRoot?.appendingPathComponent(path, isDirectory: isDirectory)
            ?? URL(fileURLWithPath: path, isDirectory: isDirectory)
        cachedURL = resolved
        return resolved
    }
    public let name: String
    /// Slash-separated, from the archive's root.
    public let path: String
    public let isDirectory: Bool
    public let isSymlink: Bool
    /// For a folder, everything inside it added up.
    public private(set) var size: Int64
    public private(set) var modified: Date?
    public private(set) var children: [Node] = []
    public private(set) weak var parent: Node?

    init(
        url: URL? = nil,
        workspaceRoot: URL? = nil,
        name: String? = nil,
        path: String,
        isDirectory: Bool,
        isSymlink: Bool,
        size: Int64,
        modified: Date?
    ) {
        self.cachedURL = url
        self.workspaceRoot = workspaceRoot
        self.name = name ?? url?.lastPathComponent ?? ""
        self.path = path
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.size = size
        self.modified = modified
    }

    /// Files and folders below this one, not counting itself.
    public var descendantCount: Int { children.reduce(children.count) { $0 + $1.descendantCount } }

    /// Reads the tree under `root`. The root node itself stands for the archive.
    public static func scan(
        _ root: URL,
        unmaterialized: [String: ZipCatalog.Entry] = [:],
        unmaterializedFolders: [String: Date?] = [:]
    ) -> Node {
        let rootExists = FileManager.default.fileExists(atPath: root.path)
        let node = Node(
            url: root, name: root.lastPathComponent, path: "", isDirectory: true, isSymlink: false, size: 0,
            modified: nil)
        if rootExists {
            node.load()
        }
        guard !unmaterialized.isEmpty || !unmaterializedFolders.isEmpty else {
            return node
        }
        node.mergeCatalog(
            workspaceRoot: root,
            entries: unmaterialized.map { (path: $0.key, entry: $0.value) },
            extraFolders: unmaterializedFolders,
            checkExistingChildren: rootExists
        )
        return node
    }

    /// Builds the `Node` tree directly from a parsed `ZipCatalog` without touching the disk.
    public static func fromCatalog(_ catalog: ZipCatalog, workspaceRoot: URL) -> Node {
        let root = Node(
            url: workspaceRoot,
            workspaceRoot: workspaceRoot,
            name: workspaceRoot.lastPathComponent,
            path: "",
            isDirectory: true,
            isSymlink: false,
            size: 0,
            modified: nil
        )
        root.populateFromCatalog(catalog.entries, workspaceRoot: workspaceRoot)
        return root
    }

    private func populateFromCatalog(_ entries: [ZipCatalog.Entry], workspaceRoot: URL) {
        var folders: [String: Node] = ["": self]
        var createdFolders: [Node] = []

        func ensureFolder(_ folderPath: String) -> Node {
            if let existing = folders[folderPath] { return existing }
            let (parentPath, folderName) = Self.splitLastSlash(folderPath)
            let parentNode = ensureFolder(parentPath)
            let folder = Node(
                workspaceRoot: workspaceRoot,
                name: folderName,
                path: folderPath,
                isDirectory: true,
                isSymlink: false,
                size: 0,
                modified: nil
            )
            folder.parent = parentNode
            parentNode.children.append(folder)
            folders[folderPath] = folder
            createdFolders.append(folder)
            return folder
        }

        var lastParentPath = ""
        var lastParentBytes: [UInt8] = []
        var lastParentNode: Node = self

        entries.withUnsafeBufferPointer { buf in
            guard let entryBase = buf.baseAddress else { return }
            let total = buf.count
            var idx = 0
            while idx < total {
                let entry = entryBase[idx]
                idx += 1
                let path = entry.path
                guard !path.isEmpty else { continue }
                if entry.isDirectory {
                    let folder = ensureFolder(path)
                    if folder.modified == nil, let mod = entry.modified {
                        folder.modified = mod
                    }
                    lastParentPath = path
                    lastParentBytes = Array(path.utf8)
                    lastParentNode = folder
                    continue
                }
                let parentNode: Node
                let leafName: String
                if !lastParentBytes.isEmpty,
                    let fastLeaf = Self.splitMatchingParent(path, expectedParent: lastParentBytes)
                {
                    parentNode = lastParentNode
                    leafName = fastLeaf
                } else {
                    let (parentPath, leaf) = Self.splitLastSlash(path)
                    leafName = leaf
                    if parentPath == lastParentPath {
                        parentNode = lastParentNode
                    } else {
                        parentNode = ensureFolder(parentPath)
                        lastParentPath = parentPath
                        lastParentBytes = Array(parentPath.utf8)
                        lastParentNode = parentNode
                    }
                }
                let childSize = Int64(clamping: entry.uncompressedSize)
                let child = Node(
                    workspaceRoot: workspaceRoot,
                    name: leafName,
                    path: path,
                    isDirectory: false,
                    isSymlink: entry.isSymlink,
                    size: childSize,
                    modified: entry.modified
                )
                child.parent = parentNode
                parentNode.children.append(child)
                parentNode.size += childSize
            }
        }

        for folder in createdFolders.reversed() {
            folder.parent?.size += folder.size
        }
    }

    private static func splitLastSlash(_ path: String) -> (parent: String, leaf: String) {
        var copy = path
        return copy.withUTF8 { buf in
            guard let base = buf.baseAddress else { return ("", path) }
            var i = buf.count - 1
            while i >= 0 {
                if base[i] == 0x2F {
                    let parent = String(decoding: UnsafeBufferPointer(start: base, count: i), as: UTF8.self)
                    let leaf = String(
                        decoding: UnsafeBufferPointer(start: base + i + 1, count: buf.count - i - 1),
                        as: UTF8.self)
                    return (parent, leaf)
                }
                i -= 1
            }
            return ("", path)
        }
    }

    private static func splitMatchingParent(_ path: String, expectedParent: [UInt8]) -> String? {
        var copy = path
        return copy.withUTF8 { buf -> String? in
            let pCount = expectedParent.count
            let n = buf.count
            guard let base = buf.baseAddress, n > pCount + 1, base[pCount] == 0x2F else { return nil }
            var i = n - 1
            while i > pCount {
                if base[i] == 0x2F { return nil }
                i -= 1
            }
            let matched = expectedParent.withUnsafeBufferPointer { pBuf -> Bool in
                guard let pBase = pBuf.baseAddress else { return false }
                return memcmp(base, pBase, pCount) == 0
            }
            guard matched else { return nil }
            return String(
                decoding: UnsafeBufferPointer(start: base.advanced(by: pCount + 1), count: n - pCount - 1),
                as: UTF8.self)
        }
    }

    private func mergeCatalog<S: Sequence>(
        workspaceRoot: URL,
        entries: S,
        extraFolders: [String: Date?],
        checkExistingChildren: Bool
    ) where S.Element == (path: String, entry: ZipCatalog.Entry) {
        var folders: [String: Node] = ["": self]
        var existingByPath: Set<String> = []
        if checkExistingChildren {
            func indexExisting(_ current: Node) {
                for child in current.children {
                    existingByPath.insert(child.path)
                    if child.isDirectory {
                        folders[child.path] = child
                        indexExisting(child)
                    }
                }
            }
            indexExisting(self)
        }

        func ensureFolder(_ folderPath: String) -> Node {
            if let existing = folders[folderPath] { return existing }
            let (parentPath, folderName) = Self.splitLastSlash(folderPath)
            let parentNode = ensureFolder(parentPath)
            let folder = Node(
                workspaceRoot: workspaceRoot,
                name: folderName,
                path: folderPath,
                isDirectory: true,
                isSymlink: false,
                size: 0,
                modified: nil
            )
            folder.parent = parentNode
            parentNode.children.append(folder)
            folders[folderPath] = folder
            if checkExistingChildren {
                existingByPath.insert(folderPath)
            }
            return folder
        }

        var lastParentPath = ""
        var lastParentBytes: [UInt8] = []
        var lastParentNode: Node = self

        for (rawPath, entry) in entries {
            let path = rawPath.utf8.last == 0x2F ? String(rawPath.dropLast()) : rawPath
            guard !path.isEmpty else { continue }
            if entry.isDirectory {
                let folder = ensureFolder(path)
                if folder.modified == nil, let mod = entry.modified {
                    folder.modified = mod
                }
                lastParentPath = path
                lastParentBytes = Array(path.utf8)
                lastParentNode = folder
                continue
            }
            if checkExistingChildren, existingByPath.contains(path) { continue }
            let parentNode: Node
            let leafName: String
            if !lastParentBytes.isEmpty, let fastLeaf = Self.splitMatchingParent(path, expectedParent: lastParentBytes)
            {
                parentNode = lastParentNode
                leafName = fastLeaf
            } else {
                let (parentPath, leaf) = Self.splitLastSlash(path)
                leafName = leaf
                if parentPath == lastParentPath {
                    parentNode = lastParentNode
                } else {
                    parentNode = ensureFolder(parentPath)
                    lastParentPath = parentPath
                    lastParentBytes = Array(parentPath.utf8)
                    lastParentNode = parentNode
                }
            }
            let child = Node(
                workspaceRoot: workspaceRoot,
                name: leafName,
                path: path,
                isDirectory: false,
                isSymlink: entry.isSymlink,
                size: Int64(clamping: entry.uncompressedSize),
                modified: entry.modified
            )
            child.parent = parentNode
            parentNode.children.append(child)
            if checkExistingChildren {
                existingByPath.insert(path)
            }
        }

        for (folderPath, mod) in extraFolders where !folderPath.isEmpty {
            let folder = ensureFolder(folderPath)
            if folder.modified == nil, let mod {
                folder.modified = mod
            }
        }

        _ = recomputeSizes()
    }

    private func recomputeSizes() -> Int64 {
        guard isDirectory else { return size }
        var total: Int64 = 0
        for child in children {
            total += child.recomputeSizes()
        }
        size = total
        return total
    }

    private func load() {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        let urls =
            (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys)) ?? []
        children = urls.filter { !EntryPath.isJunk($0.lastPathComponent) }.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isSymlink = values?.isSymbolicLink == true
            let itemName = url.lastPathComponent
            let child = Node(
                url: url,
                name: itemName,
                path: path.isEmpty ? itemName : "\(path)/\(itemName)",
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
                url: cachedURL, workspaceRoot: workspaceRoot, name: name, path: path, isDirectory: isDirectory,
                isSymlink: isSymlink, size: size, modified: modified)
            copy.children = kept
            copy.children.forEach { $0.parent = copy }
            return copy
        }
        let matches = !path.isEmpty && name.localizedStandardContains(query)
        guard matches || !kept.isEmpty || path.isEmpty else { return nil }
        let copy = Node(
            url: cachedURL, workspaceRoot: workspaceRoot, name: name, path: path, isDirectory: isDirectory,
            isSymlink: isSymlink, size: size, modified: modified)
        // A matching folder keeps all of its contents, so a search can narrow to a folder and browse it.
        copy.children = matches ? children.compactMap { $0.copied(showHiddenFiles: showHiddenFiles) } : kept
        copy.children.forEach { $0.parent = copy }
        return copy
    }

    private func copied(showHiddenFiles: Bool = true) -> Node? {
        if !path.isEmpty, !showHiddenFiles, name.hasPrefix(".") { return nil }
        let copy = Node(
            url: cachedURL, workspaceRoot: workspaceRoot, name: name, path: path, isDirectory: isDirectory,
            isSymlink: isSymlink, size: size, modified: modified)
        copy.children = children.compactMap { $0.copied(showHiddenFiles: showHiddenFiles) }
        copy.children.forEach { $0.parent = copy }
        return copy
    }

    /// Orders children by the given key, optionally keeping folders above files.
    public func sort(by key: SortKey, ascending: Bool, foldersFirst: Bool = false) {
        if children.count > 1 {
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
        }
        for child in children where child.isDirectory && !child.children.isEmpty {
            child.sort(by: key, ascending: ascending, foldersFirst: foldersFirst)
        }
    }

    private static let kindLock = NSLock()
    nonisolated(unsafe) private static var kindCache: [String: String] = [:]

    /// The localized kind Finder shows, such as "PNG image".
    public var kind: String {
        if isDirectory { return "Folder" }
        if isSymlink { return "Alias" }
        let ext = (name as NSString).pathExtension.lowercased()
        if !ext.isEmpty {
            if let cached = Self.kindLock.withLock({ Self.kindCache[ext] }) {
                return cached
            }
            if let type = UTType(filenameExtension: ext), let desc = type.localizedDescription {
                Self.kindLock.withLock { Self.kindCache[ext] = desc }
                return desc
            }
        }
        if let desc = (try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey]))?.localizedTypeDescription {
            return desc
        }
        return "Document"
    }

    public enum SortKey: String, Sendable {
        case name, size, modified, kind
    }
}
