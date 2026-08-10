import Foundation

public struct AppState: Codable, Equatable, Sendable {
    public var activeListSlug: String?
    public var anchorIndex: Int?
    public var snoozeDeadline: Date?

    public init(activeListSlug: String?, anchorIndex: Int?, snoozeDeadline: Date?) {
        self.activeListSlug = activeListSlug
        self.anchorIndex = anchorIndex
        self.snoozeDeadline = snoozeDeadline
    }
}

public enum ListStoreError: Error, Equatable {
    case listNotFound(String)
    case noActiveList
    case noAnchor
}

public struct ListStore: Sendable {
    public let rootURL: URL

    private var listsURL: URL {
        rootURL.appendingPathComponent("lists", isDirectory: true)
    }

    private var stateURL: URL {
        rootURL.appendingPathComponent("state.json")
    }

    public init(rootURL: URL? = nil) {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            self.rootURL = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Anchr", isDirectory: true)
        }
    }

    @discardableResult
    public func create(name: String, items: [Item], context: String) throws -> String {
        try ensureDirectories()
        let baseSlug = Self.slug(for: name)
        let existing = Set(try listSlugs())
        var slug = baseSlug
        var suffix = 2
        while existing.contains(slug) {
            slug = "\(baseSlug)-\(suffix)"
            suffix += 1
        }

        let directory = listURL(slug: slug)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try write(TodoList(items: items).markdown, to: directory.appendingPathComponent("list.md"))
        try write(context, to: directory.appendingPathComponent("context.md"))

        var state = try loadState()
        if state.activeListSlug == nil {
            state.activeListSlug = slug
        }
        try saveState(state)
        return slug
    }

    public func listSlugs() throws -> [String] {
        try ensureDirectories()
        let entries = try FileManager.default.contentsOfDirectory(
            at: listsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return try entries.compactMap { url in
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true,
                  FileManager.default.fileExists(atPath: url.appendingPathComponent("list.md").path)
            else { return nil }
            return url.lastPathComponent
        }.sorted()
    }

    public func switchTo(slug: String) throws {
        guard try listSlugs().contains(slug) else { throw ListStoreError.listNotFound(slug) }
        var state = try loadState()
        state.activeListSlug = slug
        state.anchorIndex = nil
        try saveState(state)
    }

    public func delete(slug: String) throws {
        guard try listSlugs().contains(slug) else { throw ListStoreError.listNotFound(slug) }
        try FileManager.default.removeItem(at: listURL(slug: slug))

        var state = try loadState()
        if state.activeListSlug == slug {
            state.activeListSlug = try listSlugs().first
            state.anchorIndex = nil
        }
        try saveState(state)
    }

    public func loadList(slug: String) throws -> TodoList {
        guard try listSlugs().contains(slug) else { throw ListStoreError.listNotFound(slug) }
        let markdown = try String(contentsOf: listURL(slug: slug).appendingPathComponent("list.md"), encoding: .utf8)
        return TodoList(markdown: markdown)
    }

    public func saveList(_ list: TodoList, slug: String) throws {
        guard try listSlugs().contains(slug) else { throw ListStoreError.listNotFound(slug) }
        try write(list.markdown, to: listURL(slug: slug).appendingPathComponent("list.md"))
    }

    public func loadContext(slug: String) throws -> String {
        guard try listSlugs().contains(slug) else { throw ListStoreError.listNotFound(slug) }
        return try String(contentsOf: listURL(slug: slug).appendingPathComponent("context.md"), encoding: .utf8)
    }

    public func saveContext(_ context: String, slug: String) throws {
        guard try listSlugs().contains(slug) else { throw ListStoreError.listNotFound(slug) }
        try write(context, to: listURL(slug: slug).appendingPathComponent("context.md"))
    }

    public func loadState() throws -> AppState {
        try ensureDirectories()
        let slugs = try listSlugs()
        guard let data = try? Data(contentsOf: stateURL),
              let decoded = try? Self.decoder.decode(AppState.self, from: data)
        else {
            return AppState(activeListSlug: slugs.first, anchorIndex: nil, snoozeDeadline: nil)
        }
        if let activeListSlug = decoded.activeListSlug, !slugs.contains(activeListSlug) {
            return AppState(activeListSlug: slugs.first, anchorIndex: nil, snoozeDeadline: nil)
        }
        return decoded
    }

    public func saveState(_ state: AppState) throws {
        try ensureDirectories()
        let data = try Self.encoder.encode(state)
        try data.write(to: stateURL, options: .atomic)
    }

    @discardableResult
    public func goSmaller(text: String) throws -> Anchor {
        var state = try loadState()
        guard let slug = state.activeListSlug else { throw ListStoreError.noActiveList }
        guard let anchorIndex = state.anchorIndex else { throw ListStoreError.noAnchor }
        var list = try loadList(slug: slug)
        guard var anchor = Anchor(index: anchorIndex, in: list) else { throw AnchorError.invalidIndex }

        try anchor.goSmaller(text: text, in: &list)
        try saveList(list, slug: slug)
        state.anchorIndex = anchor.index
        try saveState(state)
        return anchor
    }

    private func listURL(slug: String) -> URL {
        listsURL.appendingPathComponent(slug, isDirectory: true)
    }

    private func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: listsURL, withIntermediateDirectories: true)
    }

    private func write(_ string: String, to url: URL) throws {
        try Data(string.utf8).write(to: url, options: .atomic)
    }

    private static func slug(for name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var result = ""
        var needsSeparator = false
        for scalar in folded.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if needsSeparator, !result.isEmpty { result.append("-") }
                result.unicodeScalars.append(scalar)
                needsSeparator = false
            } else {
                needsSeparator = true
            }
        }
        return result.isEmpty ? "list" : result
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
