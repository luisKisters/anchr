import Foundation
import ApplicationServices
import AppKit

// Flattens the focused window's accessibility tree to text.
// Usage: axprobe --front | axprobe <bundle.id>

let MAX_NODES = 4000
let MAX_DEPTH = 40
let CAP = 3000

func attr(_ e: AXUIElement, _ name: String) -> Any? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success else { return nil }
    return v
}

func str(_ e: AXUIElement, _ name: String) -> String? {
    guard let v = attr(e, name) else { return nil }
    if let s = v as? String { return s.isEmpty ? nil : s }
    if let n = v as? NSNumber { return n.stringValue }
    return nil
}

var nodes = 0

func walk(_ e: AXUIElement, _ depth: Int, _ out: inout [String]) {
    if nodes >= MAX_NODES || depth > MAX_DEPTH { return }
    nodes += 1

    let role = str(e, kAXRoleAttribute as String) ?? "?"
    var parts: [String] = []
    for a in [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute] as [String] {
        if let s = str(e, a) {
            let clean = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty && !parts.contains(clean) { parts.append(clean) }
        }
    }
    // decorative containers with no text of their own are dropped
    if !parts.isEmpty {
        let short = role.replacingOccurrences(of: "AX", with: "")
        out.append(String(repeating: " ", count: min(depth, 12)) + short + ": " + parts.joined(separator: " | "))
    }

    if let kids = attr(e, kAXChildrenAttribute as String) as? [AXUIElement] {
        for k in kids { walk(k, depth + 1, &out) }
    }
}

guard AXIsProcessTrusted() else {
    FileHandle.standardError.write("NOT_TRUSTED: grant Accessibility to the process running this\n".data(using: .utf8)!)
    exit(3)
}

let arg = CommandLine.arguments.dropFirst().first ?? "--front"
var app: NSRunningApplication?
if arg == "--front" {
    app = NSWorkspace.shared.frontmostApplication
} else {
    app = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == arg }
}
guard let app, let pid = Optional(app.processIdentifier) else {
    FileHandle.standardError.write("NOT_RUNNING: \(arg)\n".data(using: .utf8)!)
    exit(4)
}

let axApp = AXUIElementCreateApplication(pid)
// the switch that makes Chrome / Electron build their renderer tree
AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
// Chrome and other Chromium shells watch this one instead
AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
usleep(1_200_000)

var target = axApp
if let w = attr(axApp, kAXFocusedWindowAttribute as String) {
    target = (w as! AXUIElement)
} else if let ws = attr(axApp, kAXWindowsAttribute as String) as? [AXUIElement], let first = ws.first {
    target = first
}

let title = str(target, kAXTitleAttribute as String) ?? "(no title)"
var lines: [String] = []
walk(target, 0, &lines)

let text = lines.joined(separator: "\n")
let capped = String(text.prefix(CAP))
let name = app.localizedName ?? "?"

print("=== \(name) [\(app.bundleIdentifier ?? "?")]")
print("=== window: \(title)")
print("=== nodes: \(nodes)  lines: \(lines.count)  chars: \(text.count)  (capped at \(CAP))")
print(capped)
