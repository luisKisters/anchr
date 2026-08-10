import AppKit
import AnchrCore
import Foundation

guard AXSnapshotWalker.isProcessTrusted else {
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

let reader = DelayedAXSnapshotReader()
do {
    try reader.applicationDidBecomeFrontmost(processIdentifier: pid)
} catch {
    FileHandle.standardError.write("PREPARE_FAILED: \(error.localizedDescription)\n".data(using: .utf8)!)
    exit(5)
}

// The probe emulates the next scheduled check. It does not read in the same
// call that enables accessibility because Electron builds its tree later.
usleep(1_200_000)

do {
    guard let result = try reader.snapshotForCheck(processIdentifier: pid) else {
        FileHandle.standardError.write("NOT_READY: accessibility was enabled; run the next check later\n".data(using: .utf8)!)
        exit(6)
    }
    print("=== \(app.localizedName ?? "?") [\(app.bundleIdentifier ?? "?")]")
    print("=== window: \(result.windowTitle ?? "(no title)")")
    print("=== nodes: \(result.visitedNodeCount)  lines: \(result.lineCount)  chars: \(result.usefulCharacterCount)  (capped at \(AXSnapshotWalker.defaultMaximumCharacters))")
    print(result.text)
} catch {
    FileHandle.standardError.write("SNAPSHOT_FAILED: \(error.localizedDescription)\n".data(using: .utf8)!)
    exit(7)
}
