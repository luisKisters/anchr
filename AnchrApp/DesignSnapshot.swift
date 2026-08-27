import AnchrKit
import AppKit
import SwiftUI

enum DesignSnapshotRequest: String {
    case overlayList = "overlay/list"
    case overlayCreate = "overlay/create"
    case overlaySwitcher = "overlay/switcher"
    case interventionAsk = "intervention/ask"
    case interventionSmaller = "intervention/smaller"
    case onboardingPermission = "onboarding/permission"

    static var current: DesignSnapshotRequest? {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--design-snapshot"),
              arguments.indices.contains(flag + 1)
        else { return nil }
        return DesignSnapshotRequest(rawValue: arguments[flag + 1])
    }
}

enum DesignSnapshotError: Error {
    case renderFailed
}

@MainActor
enum DesignSnapshotRenderer {
    static func render(_ request: DesignSnapshotRequest) throws {
        switch request {
        case .overlayList:
            try renderList()
        case .overlayCreate:
            let model = previewModel(mode: .create(onboarding: false))
            model.createName = "Corvus — deal analysis"
            model.createPlan = "- [ ] Review the analysis draft\n- [ ] Send the extraction to Robin"
            try render(model, name: "overlay-create")
        case .overlaySwitcher:
            let model = previewModel(mode: .switcher)
            model.switcher = SwitcherState(lists: [
                ListSummary(slug: "corvus", name: "Corvus — deal analysis", openItemCount: 6, hasContext: true),
                ListSummary(slug: "anchr", name: "Anchr", openItemCount: 3, hasContext: true),
                ListSummary(slug: "uni", name: "Uni — Statistik", openItemCount: 2, hasContext: false),
            ], selectedSlug: "corvus")
            try render(model, name: "overlay-switcher")
        case .interventionAsk:
            let model = previewModel(mode: .intervention)
            model.intervention = previewIntervention()
            try render(model, name: "intervention-ask")
        case .interventionSmaller:
            let model = previewModel(mode: .intervention)
            var state = previewIntervention()
            _ = Intervention.reduce(&state, key: .answerSmaller)
            model.intervention = state
            try render(model, name: "intervention-smaller")
        case .onboardingPermission:
            try render(previewModel(mode: .onboardingPermission), name: "onboarding-permission")
        }
    }

    private static func renderList() throws {
        let list = TodoList(items: [
            Item(text: "Make the analysis up to date", depth: 0, done: true),
            Item(text: "All companies correct — no unanalyzed context", depth: 1, done: true),
            Item(text: "Exclude Northwind and every company Sam had contact with today", depth: 1, done: true),
            Item(text: "Review the analysis draft in Notion", depth: 0, done: false),
            Item(text: "Send the current extraction to Robin", depth: 0, done: false),
            Item(text: "Robin then:", depth: 0, done: false),
            Item(text: "Sends it to Sam for review", depth: 1, done: false),
            Item(text: "Asks Nadia if she has context on the deals", depth: 1, done: false),
            Item(text: "Asks Sam for a to-do list we can see", depth: 1, done: false),
            Item(text: "Bench Sam's existing list", depth: 2, done: false),
        ])
        let state = ListEditorState(list: list, selection: 4, anchorIndex: 4)
        let model = ListEditorModel(previewState: state, listName: "Corvus — deal analysis")
        let flow = OverlayFlowModel(preview: .list, editor: model)
        try render(flow, name: "overlay-list")
    }

    private static func previewModel(mode: OverlayMode) -> OverlayFlowModel {
        let editor = ListEditorModel(
            previewState: ListEditorState(list: TodoList(items: []), selection: nil, anchorIndex: nil),
            listName: "Preview"
        )
        return OverlayFlowModel(preview: mode, editor: editor)
    }

    private static func previewIntervention() -> InterventionState {
        InterventionState(
            anchor: "Send the current extraction to Robin",
            evidence: "YOUTUBE · 4 MIN",
            smallerStep: "Export the v3 sheet as CSV"
        )
    }

    private static func render(_ model: OverlayFlowModel, name: String) throws {
        let content = OverlayFlowView(model: model, snapshotMode: true) {}
            .frame(width: 1200, height: 800)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        guard let image = renderer.nsImage,
              let data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data),
              let png = bitmap.representation(using: .png, properties: [:])
        else { throw DesignSnapshotError.renderFailed }

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let directory = root.appendingPathComponent("design/snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent("\(name).png"), options: .atomic)
    }
}
