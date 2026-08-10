import Foundation

public struct Item: Equatable, Sendable {
    public var text: String
    public var depth: Int
    public var done: Bool

    public init(text: String, depth: Int, done: Bool) {
        self.text = text
        self.depth = max(0, depth)
        self.done = done
    }
}

public struct TodoList: Equatable, Sendable {
    private enum LayoutLine: Equatable, Sendable {
        case item(Int)
        case raw(String)
    }

    public var items: [Item]
    private var layout: [LayoutLine]
    private var hasFinalNewline: Bool

    public init(items: [Item]) {
        self.items = Self.clamped(items)
        layout = self.items.indices.map(LayoutLine.item)
        hasFinalNewline = !items.isEmpty
    }

    public init(markdown: String) {
        hasFinalNewline = markdown.hasSuffix("\n")

        var lines = markdown.components(separatedBy: "\n")
        if hasFinalNewline {
            lines.removeLast()
        }
        if markdown.isEmpty {
            lines = []
        }

        var parsedItems: [Item] = []
        var parsedLayout: [LayoutLine] = []
        for line in lines {
            guard var item = Self.parseFixedLine(line) else {
                parsedLayout.append(.raw(line))
                continue
            }

            let previousDepth = parsedItems.last?.depth ?? -1
            item.depth = max(0, min(item.depth, previousDepth + 1))
            parsedLayout.append(.item(parsedItems.count))
            parsedItems.append(item)
        }

        items = parsedItems
        layout = parsedLayout
    }

    public var markdown: String {
        let lines: [String]
        if hasValidLayout {
            lines = layout.map { line in
                switch line {
                case let .item(index):
                    Self.render(items[index])
                case let .raw(value):
                    value
                }
            }
        } else {
            lines = items.map(Self.render)
        }

        guard !lines.isEmpty else {
            return hasFinalNewline ? "\n" : ""
        }
        return lines.joined(separator: "\n") + (hasFinalNewline ? "\n" : "")
    }

    public mutating func insert(_ item: Item, at index: Int) {
        precondition(items.indices.contains(index) || index == items.endIndex)

        if !hasValidLayout {
            layout = items.indices.map(LayoutLine.item)
        }

        let insertionPosition: Int
        if index == 0 {
            insertionPosition = layout.firstIndex { line in
                if case .item = line { return true }
                return false
            } ?? layout.endIndex
        } else {
            let previousPosition = layout.lastIndex(of: .item(index - 1))
            insertionPosition = previousPosition.map { layout.index(after: $0) } ?? layout.endIndex
        }

        layout = layout.map { line in
            guard case let .item(existingIndex) = line, existingIndex >= index else {
                return line
            }
            return .item(existingIndex + 1)
        }
        layout.insert(.item(index), at: insertionPosition)
        items.insert(item, at: index)
        hasFinalNewline = true
    }

    public static func normalize(pasted: String) -> [Item] {
        let rawLines = pasted
            .replacingOccurrences(of: "\r", with: "")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard !rawLines.isEmpty else { return [] }

        let widths = rawLines.map(Self.leadingIndentWidth)
        let positiveWidths = widths.filter { $0 > 0 }
        let indentUnit = min(positiveWidths.min() ?? 4, 4)

        var output: [Item] = []
        for (rawLine, width) in zip(rawLines, widths) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            var depth = Int((Double(width) / Double(indentUnit)).rounded())

            if line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) != nil {
                line = replacingFirstMatch(in: line, pattern: #"^#{1,6}\s+"#, with: "")
                depth = 0
            }

            line = replacingFirstMatch(
                in: line,
                pattern: #"^([-*+•–]|[0-9]+[.)])\s+"#,
                with: ""
            )

            var done = false
            if let checkbox = line.range(of: #"^\[([ xX])\]\s*"#, options: .regularExpression) {
                let marker = line[checkbox].lowercased()
                done = marker.contains("x")
                line.removeSubrange(checkbox)
            }

            line = flattenWikiLinks(in: line)
            line = replacingMatches(in: line, pattern: #"\*\*(.+?)\*\*"#, with: "$1")
                .trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            let previousDepth = output.last?.depth ?? -1
            output.append(Item(text: line, depth: max(0, min(depth, previousDepth + 1)), done: done))
        }
        return output
    }

    private var hasValidLayout: Bool {
        let indices = layout.compactMap { line -> Int? in
            guard case let .item(index) = line else { return nil }
            return index
        }
        return indices.count == items.count && indices.sorted() == Array(items.indices)
    }

    private static func parseFixedLine(_ line: String) -> Item? {
        let leadingSpaces = line.prefix { $0 == " " }.count
        let content = line.dropFirst(leadingSpaces)

        let done: Bool
        let text: Substring
        if content.hasPrefix("- [ ] ") {
            done = false
            text = content.dropFirst(6)
        } else if content.hasPrefix("- [x] ") {
            done = true
            text = content.dropFirst(6)
        } else {
            return nil
        }

        return Item(text: String(text), depth: leadingSpaces / 2, done: done)
    }

    private static func render(_ item: Item) -> String {
        String(repeating: "  ", count: max(0, item.depth))
            + (item.done ? "- [x] " : "- [ ] ")
            + item.text
    }

    private static func clamped(_ items: [Item]) -> [Item] {
        var result: [Item] = []
        for var item in items {
            item.depth = max(0, min(item.depth, (result.last?.depth ?? -1) + 1))
            result.append(item)
        }
        return result
    }

    private static func leadingIndentWidth(_ line: String) -> Int {
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        if indent.contains("\t") {
            return indent.filter { $0 == "\t" }.count * 4
        }
        return indent.count
    }
}

private func replacingFirstMatch(in value: String, pattern: String, with replacement: String) -> String {
    guard let range = value.range(of: pattern, options: .regularExpression) else { return value }
    return value.replacingCharacters(in: range, with: replacement)
}

private func replacingMatches(in value: String, pattern: String, with replacement: String) -> String {
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return value }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return expression.stringByReplacingMatches(in: value, range: range, withTemplate: replacement)
}

private func flattenWikiLinks(in value: String) -> String {
    var result = value
    while let range = result.range(of: #"\[\[[^\]]+\]\]"#, options: .regularExpression) {
        let link = result[range].dropFirst(2).dropLast(2)
        let parts = link.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let replacement = parts.count == 2 ? String(parts[1]) : String(parts[0])
        result.replaceSubrange(range, with: replacement)
    }
    return result
}
