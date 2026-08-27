import ApplicationServices
import Foundation

public struct AXSnapshotNode: Equatable, Sendable {
    public let role: String
    public let title: String?
    public let value: String?
    public let description: String?
    public let children: [AXSnapshotNode]

    public init(
        role: String,
        title: String? = nil,
        value: String? = nil,
        description: String? = nil,
        children: [AXSnapshotNode] = []
    ) {
        self.role = role
        self.title = title
        self.value = value
        self.description = description
        self.children = children
    }
}

public struct AXSnapshotResult: Equatable, Sendable {
    public let text: String
    public let visitedNodeCount: Int
    public let lineCount: Int
    public let usefulCharacterCount: Int
    public let windowTitle: String?

    public init(
        text: String,
        visitedNodeCount: Int,
        lineCount: Int,
        usefulCharacterCount: Int,
        windowTitle: String? = nil
    ) {
        self.text = text
        self.visitedNodeCount = visitedNodeCount
        self.lineCount = lineCount
        self.usefulCharacterCount = usefulCharacterCount
        self.windowTitle = windowTitle
    }
}

public enum AXSnapshotError: Error, Equatable, LocalizedError {
    case notTrusted
    case applicationUnavailable(Int32)

    public var errorDescription: String? {
        switch self {
        case .notTrusted:
            return "Accessibility permission is not granted"
        case let .applicationUnavailable(processIdentifier):
            return "No accessibility window is available for process \(processIdentifier)"
        }
    }
}

public enum AXSnapshotWalker {
    public static let defaultMaximumCharacters = 3_000
    public static let defaultMaximumNodes = 4_000
    public static let defaultMaximumDepth = 40

    public static var isProcessTrusted: Bool {
        AXIsProcessTrusted()
    }

    public static func flatten(
        _ root: AXSnapshotNode,
        maximumCharacters: Int = defaultMaximumCharacters,
        maximumNodes: Int = defaultMaximumNodes,
        maximumDepth: Int = defaultMaximumDepth
    ) -> AXSnapshotResult {
        var lines: [String] = []
        var visitedNodeCount = 0

        func walk(_ node: AXSnapshotNode, depth: Int) {
            guard visitedNodeCount < maximumNodes, depth <= maximumDepth else {
                return
            }
            visitedNodeCount += 1

            let parts = [node.title, node.value, node.description]
                .compactMap(cleaned)
                .reduce(into: [String]()) { uniqueParts, part in
                    if !uniqueParts.contains(part) {
                        uniqueParts.append(part)
                    }
                }

            if !parts.isEmpty {
                let role = node.role.hasPrefix("AX")
                    ? String(node.role.dropFirst(2))
                    : node.role
                let indentation = String(repeating: " ", count: min(depth, 12))
                lines.append("\(indentation)\(role): \(parts.joined(separator: " | "))")
            }

            for child in node.children {
                walk(child, depth: depth + 1)
            }
        }

        walk(root, depth: 0)
        let fullText = lines.joined(separator: "\n")
        let limit = max(0, maximumCharacters)
        return AXSnapshotResult(
            text: String(fullText.prefix(limit)),
            visitedNodeCount: visitedNodeCount,
            lineCount: lines.count,
            usefulCharacterCount: fullText.count
        )
    }

    public static func prepareApplication(processIdentifier: Int32) throws {
        guard isProcessTrusted else {
            throw AXSnapshotError.notTrusted
        }

        let application = AXUIElementCreateApplication(processIdentifier)
        _ = AXUIElementSetAttributeValue(
            application,
            "AXManualAccessibility" as CFString,
            kCFBooleanTrue
        )
        _ = AXUIElementSetAttributeValue(
            application,
            "AXEnhancedUserInterface" as CFString,
            kCFBooleanTrue
        )
    }

    public static func snapshot(
        processIdentifier: Int32,
        maximumCharacters: Int = defaultMaximumCharacters
    ) throws -> AXSnapshotResult {
        guard isProcessTrusted else {
            throw AXSnapshotError.notTrusted
        }

        let application = AXUIElementCreateApplication(processIdentifier)
        guard let window = focusedWindow(for: application) else {
            throw AXSnapshotError.applicationUnavailable(processIdentifier)
        }

        var remainingNodes = defaultMaximumNodes
        let root = makeNode(
            from: window,
            depth: 0,
            remainingNodes: &remainingNodes
        )
        var result = flatten(root, maximumCharacters: maximumCharacters)
        result = AXSnapshotResult(
            text: result.text,
            visitedNodeCount: result.visitedNodeCount,
            lineCount: result.lineCount,
            usefulCharacterCount: result.usefulCharacterCount,
            windowTitle: stringAttribute(window, kAXTitleAttribute as String)
        )
        return result
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let cleanedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedValue.isEmpty ? nil : cleanedValue
    }

    private static func focusedWindow(for application: AXUIElement) -> AXUIElement? {
        if let focused = attribute(application, kAXFocusedWindowAttribute as String) {
            return (focused as! AXUIElement)
        }
        if let windows = attribute(application, kAXWindowsAttribute as String) as? [AXUIElement] {
            return windows.first
        }
        return nil
    }

    private static func makeNode(
        from element: AXUIElement,
        depth: Int,
        remainingNodes: inout Int
    ) -> AXSnapshotNode {
        guard remainingNodes > 0, depth <= defaultMaximumDepth else {
            return AXSnapshotNode(role: "AXGroup")
        }
        remainingNodes -= 1

        var children: [AXSnapshotNode] = []
        if depth < defaultMaximumDepth,
           let elements = attribute(element, kAXChildrenAttribute as String) as? [AXUIElement] {
            for child in elements {
                guard remainingNodes > 0 else { break }
                children.append(makeNode(
                    from: child,
                    depth: depth + 1,
                    remainingNodes: &remainingNodes
                ))
            }
        }

        return AXSnapshotNode(
            role: stringAttribute(element, kAXRoleAttribute as String) ?? "AXUnknown",
            title: stringAttribute(element, kAXTitleAttribute as String),
            value: stringAttribute(element, kAXValueAttribute as String),
            description: stringAttribute(element, kAXDescriptionAttribute as String),
            children: children
        )
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> Any? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        guard let value = attribute(element, name) else {
            return nil
        }
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }
}

protocol AXSnapshotAccess: AnyObject {
    func prepare(processIdentifier: Int32) throws
    func read(processIdentifier: Int32) throws -> AXSnapshotResult
}

private final class LiveAXSnapshotAccess: AXSnapshotAccess {
    func prepare(processIdentifier: Int32) throws {
        try AXSnapshotWalker.prepareApplication(processIdentifier: processIdentifier)
    }

    func read(processIdentifier: Int32) throws -> AXSnapshotResult {
        try AXSnapshotWalker.snapshot(processIdentifier: processIdentifier)
    }
}

@MainActor
public protocol ObservationSnapshotting: AnyObject {
    func applicationDidBecomeFrontmost(processIdentifier: Int32) throws
    func snapshotForCheck(processIdentifier: Int32) throws -> AXSnapshotResult?
}

@MainActor
public final class DelayedAXSnapshotReader: ObservationSnapshotting {
    private let access: AXSnapshotAccess
    private var preparedProcessIdentifier: Int32?

    public convenience init() {
        self.init(access: LiveAXSnapshotAccess())
    }

    init(access: AXSnapshotAccess) {
        self.access = access
    }

    public func applicationDidBecomeFrontmost(processIdentifier: Int32) throws {
        preparedProcessIdentifier = nil
        try access.prepare(processIdentifier: processIdentifier)
        preparedProcessIdentifier = processIdentifier
    }

    public func snapshotForCheck(processIdentifier: Int32) throws -> AXSnapshotResult? {
        guard preparedProcessIdentifier == processIdentifier else {
            try applicationDidBecomeFrontmost(processIdentifier: processIdentifier)
            return nil
        }
        return try access.read(processIdentifier: processIdentifier)
    }
}
