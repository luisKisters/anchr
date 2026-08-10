import Foundation

public enum AnchorError: Error, Equatable {
    case invalidIndex
    case emptyText
}

public struct Anchor: Equatable, Sendable {
    public private(set) var index: Int
    public private(set) var parentIndices: [Int]

    public init?(index: Int, in list: TodoList) {
        guard list.items.indices.contains(index) else { return nil }

        self.index = index
        var parents: [Int] = []
        var requiredDepth = list.items[index].depth - 1
        if requiredDepth >= 0 {
            for candidate in stride(from: index - 1, through: 0, by: -1) {
                if list.items[candidate].depth == requiredDepth {
                    parents.append(candidate)
                    requiredDepth -= 1
                    if requiredDepth < 0 { break }
                }
            }
        }
        parentIndices = parents.reversed()
    }

    public func parentItems(in list: TodoList) -> [Item] {
        parentIndices.compactMap { index in
            guard list.items.indices.contains(index) else { return nil }
            return list.items[index]
        }
    }

    public mutating func goSmaller(text: String, in list: inout TodoList) throws {
        guard list.items.indices.contains(index) else { throw AnchorError.invalidIndex }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AnchorError.emptyText }

        let anchorDepth = list.items[index].depth
        var insertionIndex = index + 1
        while insertionIndex < list.items.count, list.items[insertionIndex].depth > anchorDepth {
            insertionIndex += 1
        }

        list.insert(Item(text: text, depth: anchorDepth + 1, done: false), at: insertionIndex)
        guard let newAnchor = Anchor(index: insertionIndex, in: list) else {
            throw AnchorError.invalidIndex
        }
        self = newAnchor
    }
}
