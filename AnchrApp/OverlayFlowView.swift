import AnchrCore
import AnchrKit
import AppKit
import SwiftUI

enum OverlayMode: Equatable {
    case list
    case switcher
    case create(onboarding: Bool)
    case context
    case intervention
    case onboardingPermission
    case onboardingKey
}

@MainActor
final class OverlayFlowModel: ObservableObject {
    @Published var mode: OverlayMode
    @Published var editor: ListEditorModel
    @Published var switcher = SwitcherState(lists: [], selectedSlug: nil)
    @Published var intervention: InterventionState?
    @Published var createName = ""
    @Published var createPlan = ""
    @Published var createContext = ""
    @Published var showsCreateContext = false
    @Published var contextName = ""
    @Published var contextText = ""
    @Published var statusMessage: String?
    @Published var isCheckingKey = false

    private let store: ListStore
    private var contextSlug: String?

    init(store: ListStore = ListStore(rootURL: AppSupportRoot.url)) {
        self.store = store
        editor = ListEditorModel(store: store)
        let hasLists = ((try? store.listSlugs()) ?? []).isEmpty == false
        mode = hasLists ? .list : .onboardingPermission
    }

    init(preview mode: OverlayMode, editor: ListEditorModel) {
        self.mode = mode
        self.editor = editor
        store = ListStore(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    func showSwitcher() {
        let selected = try? store.loadState().activeListSlug
        switcher = SwitcherState(lists: (try? store.listSummaries()) ?? [], selectedSlug: selected)
        mode = .switcher
    }

    func sendSwitcher(_ key: SwitcherKey) {
        guard let effect = Switcher.reduce(&switcher, key: key) else {
            objectWillChange.send()
            return
        }
        switch effect {
        case let .openList(slug):
            try? store.switchTo(slug: slug)
            editor = ListEditorModel(store: store)
            mode = .list
        case let .editContext(slug):
            contextSlug = slug
            contextName = switcher.lists.first { $0.slug == slug }?.name ?? slug
            contextText = (try? store.loadContext(slug: slug)) ?? ""
            mode = .context
        case .createList:
            beginCreate(onboarding: false)
        case .back:
            mode = .list
        }
    }

    func beginCreate(onboarding: Bool) {
        createName = ""
        createPlan = ""
        createContext = ""
        showsCreateContext = false
        statusMessage = nil
        mode = .create(onboarding: onboarding)
    }

    func createList(onboarding: Bool) {
        let items = TodoList.normalize(pasted: createPlan)
        guard !items.isEmpty else {
            statusMessage = "Paste at least one task."
            return
        }
        do {
            let slug = try store.createFromPaste(
                name: createName,
                pasted: createPlan,
                context: createContext.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            let anchorIndex = items.firstIndex { !$0.done } ?? 0
            try store.saveState(AppState(activeListSlug: slug, anchorIndex: anchorIndex, snoozeDeadline: nil))
            editor = ListEditorModel(store: store)
            statusMessage = nil
            mode = .list
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func saveContext() {
        guard let contextSlug else { return }
        do {
            try store.saveContext(contextText.trimmingCharacters(in: .whitespacesAndNewlines), slug: contextSlug)
            showSwitcher()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func showIntervention(_ verdict: Verdict) {
        guard let appState = try? store.loadState(),
              let slug = appState.activeListSlug,
              let index = appState.anchorIndex,
              let list = try? store.loadList(slug: slug),
              list.items.indices.contains(index)
        else { return }
        intervention = InterventionState(
            anchor: list.items[index].text,
            evidence: verdict.evidence.uppercased(),
            smallerStep: verdict.smallerStep
        )
        mode = .intervention
    }

    func sendIntervention(_ key: InterventionKey) -> Bool {
        guard var state = intervention else { return false }
        let effect = Intervention.reduce(&state, key: key)
        intervention = state
        guard let effect else { return false }
        do {
            switch effect {
            case .snooze:
                try store.snooze(until: Date().addingTimeInterval(600))
            case let .goSmaller(text):
                try store.goSmaller(text: text)
            case let .setNewAnchor(text):
                try store.setNewAnchor(text: text)
            }
            editor = ListEditorModel(store: store)
            mode = .list
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    func continueFromPermission() {
        if AccessibilityPermission.currentStatus == .granted {
            statusMessage = nil
            mode = .onboardingKey
        } else {
            statusMessage = "Accessibility permission is not granted."
        }
    }

    func verifyOpenRouter() async {
        guard !isCheckingKey else { return }
        isCheckingKey = true
        statusMessage = nil
        defer { isCheckingKey = false }

        let pasted = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if pasted.hasPrefix("sk-or-") {
            do {
                try OpenRouterKey.store(pasted)
            } catch {
                statusMessage = "Could not save the key: \(error.localizedDescription)"
                return
            }
        }

        guard OpenRouterKey.load() != nil else {
            statusMessage = "Copy your key from openrouter.ai/keys, then press Check again."
            return
        }

        do {
            _ = try await OpenRouterClassifier().classify(Observation(
                anchor: "Connect OpenRouter",
                parentChain: [],
                projectContext: "Anchr onboarding",
                openItems: ["Paste the first plan"],
                accessibilityText: "Anchr onboarding"
            ))
            beginCreate(onboarding: true)
        } catch let error as OpenRouterClassifier.Error {
            switch error {
            case .missingAPIKey:
                statusMessage = "Copy your key from openrouter.ai/keys, then press Check again."
            case .httpStatus(401, _), .httpStatus(403, _):
                statusMessage = "OpenRouter rejected that key. Copy a valid one and press Check again."
            case .httpStatus(402, _):
                statusMessage = "That OpenRouter account has no credit left."
            case .timedOut:
                statusMessage = "OpenRouter did not answer in time. Check your connection."
            default:
                statusMessage = "OpenRouter check failed: \(error)"
            }
        } catch {
            statusMessage = "OpenRouter check failed: \(error.localizedDescription)"
        }
    }
}

struct OverlayFlowView: View {
    @ObservedObject var model: OverlayFlowModel
    let snapshotMode: Bool
    let onClose: () -> Void

    var body: some View {
        Group {
            switch model.mode {
            case .list:
                ListEditorView(
                    model: model.editor,
                    snapshotMode: snapshotMode,
                    onClose: onClose,
                    onSwitcher: model.showSwitcher
                )
            case .switcher:
                SwitcherView(model: model, snapshotMode: snapshotMode)
            case let .create(onboarding):
                CreateListView(model: model, onboarding: onboarding, snapshotMode: snapshotMode)
            case .context:
                ContextView(model: model, snapshotMode: snapshotMode)
            case .intervention:
                InterventionView(model: model, snapshotMode: snapshotMode, onClose: onClose)
            case .onboardingPermission:
                OnboardingPermissionView(model: model, snapshotMode: snapshotMode)
            case .onboardingKey:
                OnboardingKeyView(model: model, snapshotMode: snapshotMode)
            }
        }
    }
}

private struct OverlayBackdrop<Content: View>: View {
    let heavy: Bool
    let snapshotMode: Bool
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            if snapshotMode {
                Rectangle().fill(.black).ignoresSafeArea()
            } else {
                Rectangle()
                    .fill(.black.opacity(heavy ? 0.66 : 0.34))
                    .background(heavy ? .ultraThinMaterial : .thinMaterial)
                    .ignoresSafeArea()
            }
            content
        }
        .foregroundStyle(.white)
    }
}

private struct SwitcherView: View {
    @ObservedObject var model: OverlayFlowModel
    let snapshotMode: Bool

    var body: some View {
        OverlayBackdrop(heavy: false, snapshotMode: snapshotMode) {
            VStack(spacing: 0) {
                header("Lists", meta: "⌘K")
                VStack(spacing: 0) {
                    ForEach(model.switcher.lists.indices, id: \.self) { index in
                        let list = model.switcher.lists[index]
                        HStack {
                            Text(list.name)
                            Spacer()
                            Text("\(list.openItemCount) OPEN   \(list.hasContext ? "CONTEXT" : "NO CONTEXT")")
                                .font(.caption2.monospaced())
                                .tracking(0.6)
                                .foregroundStyle(.white.opacity(0.24))
                        }
                        .padding(.vertical, 9)
                        .padding(.horizontal, 12)
                        .background {
                            if index == model.switcher.selection {
                                RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.07))
                            }
                        }
                        .overlay(alignment: .leading) {
                            if index == model.switcher.selection {
                                Rectangle().fill(.white).frame(width: 2)
                            }
                        }
                    }
                }
                .padding(.top, 14)
                hints(["↑↓ MOVE", "↵ OPEN", "C CONTEXT", "N NEW LIST", "ESC BACK"])
            }
            .frame(width: 520)
            .background {
                if !snapshotMode {
                    FlowKeyCapture { event in
                        if let key = event.switcherKey { model.sendSwitcher(key) }
                    }
                }
            }
        }
    }
}

private struct CreateListView: View {
    @ObservedObject var model: OverlayFlowModel
    let onboarding: Bool
    let snapshotMode: Bool

    var body: some View {
        OverlayBackdrop(heavy: false, snapshotMode: snapshotMode) {
            VStack(spacing: 0) {
                header(onboarding ? "Your first list" : "New list", meta: "PASTE A PLAN")
                VStack(spacing: 18) {
                    if snapshotMode {
                        Text(model.createName.isEmpty ? "Name" : model.createName)
                            .font(.title3)
                            .foregroundStyle(model.createName.isEmpty ? .white.opacity(0.24) : .white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(model.createPlan.isEmpty
                             ? "Paste your plan. Any format — bullets, numbers, tabs, checkboxes."
                             : model.createPlan)
                            .foregroundStyle(model.createPlan.isEmpty ? .white.opacity(0.24) : .white)
                            .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
                    } else {
                        TextField("Name", text: $model.createName)
                            .textFieldStyle(.plain)
                            .font(.title3)
                        TextEditor(text: $model.createPlan)
                            .scrollContentBackground(.hidden)
                            .frame(height: 230)
                            .overlay(alignment: .topLeading) {
                                if model.createPlan.isEmpty {
                                    Text("Paste your plan. Any format — bullets, numbers, tabs, checkboxes.")
                                        .foregroundStyle(.white.opacity(0.24))
                                        .allowsHitTesting(false)
                                        .padding(.top, 8)
                                        .padding(.leading, 5)
                                }
                            }
                    }
                    if model.showsCreateContext {
                        TextEditor(text: $model.createContext)
                            .scrollContentBackground(.hidden)
                            .frame(height: 100)
                    } else {
                        Button("+ CONTEXT") { model.showsCreateContext = true }
                            .buttonStyle(.plain)
                            .font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    status(model.statusMessage)
                }
                .padding(.vertical, 24)
                hints(["⌘↵ CREATE", onboarding ? "" : "ESC BACK"])
            }
            .frame(width: 720)
            .onKeyPress(keys: [.return]) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                model.createList(onboarding: onboarding)
                return .handled
            }
            .onExitCommand {
                if !onboarding { model.showSwitcher() }
            }
        }
    }
}

private struct ContextView: View {
    @ObservedObject var model: OverlayFlowModel
    let snapshotMode: Bool

    var body: some View {
        OverlayBackdrop(heavy: false, snapshotMode: snapshotMode) {
            VStack(spacing: 0) {
                header(model.contextName, meta: "CONTEXT")
                TextEditor(text: $model.contextText)
                    .scrollContentBackground(.hidden)
                    .frame(height: 260)
                    .padding(.vertical, 24)
                hints(["⌘↵ SAVE", "ESC BACK"])
            }
            .frame(width: 720)
            .onKeyPress(keys: [.return]) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                model.saveContext()
                return .handled
            }
            .onExitCommand { model.showSwitcher() }
        }
    }
}

private struct InterventionView: View {
    @ObservedObject var model: OverlayFlowModel
    let snapshotMode: Bool
    let onClose: () -> Void

    var body: some View {
        OverlayBackdrop(heavy: true, snapshotMode: snapshotMode) {
            if let state = model.intervention {
                VStack(alignment: .leading, spacing: 0) {
                    Text(interventionSeen(state))
                        .font(.caption.monospaced())
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.48))
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(interventionTag(state))
                            .font(.caption2.monospaced())
                            .tracking(1.2)
                        Text(state.anchor)
                    }
                    .foregroundStyle(.white.opacity(0.24))
                    .padding(.top, 34)
                    Text(interventionQuestion(state))
                        .font(.largeTitle)
                        .fontWeight(.medium)
                        .padding(.top, 10)

                    switch state.stage {
                    case .asking:
                        HStack(spacing: 10) {
                            answer("Back to it", key: .answerBack, primary: true)
                            answer("Go smaller", key: .answerSmaller)
                            answer("New anchor", key: .answerNewAnchor)
                        }
                        .padding(.top, 34)
                        Text("1 · 2 · 3   NO ESC")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.white.opacity(0.24))
                            .padding(.top, 16)
                    case let .editing(_, text):
                        Group {
                            if snapshotMode {
                                Text(text)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                TextField("", text: Binding(
                                    get: { text },
                                    set: { _ = model.sendIntervention(.replaceText($0)) }
                                ))
                                .textFieldStyle(.plain)
                                .onSubmit {
                                    if model.sendIntervention(.submit) { onClose() }
                                }
                            }
                        }
                        .font(.title3)
                        .padding(.top, 30)
                        .padding(.bottom, 9)
                        .overlay(alignment: .bottom) { Divider().overlay(.white.opacity(0.35)) }
                        Text("↵ SET · WRITTEN INTO THE LIST UNDER THE OLD ANCHOR")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.white.opacity(0.24))
                            .padding(.top, 16)
                    }
                }
                .frame(width: 560)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeOut(duration: 0.42), value: state.stage)
                .background {
                    if !snapshotMode {
                        FlowKeyCapture { event in
                            guard case .asking = state.stage, let key = event.interventionKey else { return }
                            if model.sendIntervention(key) { onClose() }
                        }
                    }
                }
            }
        }
    }

    private func answer(_ title: String, key: InterventionKey, primary: Bool = false) -> some View {
        Button(title) {
            if model.sendIntervention(key) { onClose() }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 10)
        .padding(.horizontal, 18)
        .foregroundStyle(primary ? .black : .white)
        .background(primary ? .white : .clear)
        .overlay { RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(primary ? 1 : 0.28)) }
    }

    private func interventionSeen(_ state: InterventionState) -> String {
        if case let .editing(kind, _) = state.stage {
            return kind == .smaller ? "ANCHR · SUGGESTED" : "NEW ANCHOR"
        }
        return state.evidence
    }

    private func interventionTag(_ state: InterventionState) -> String {
        if case .editing = state.stage { return "WAS" }
        return "ANCHOR"
    }

    private func interventionQuestion(_ state: InterventionState) -> String {
        switch state.stage {
        case .asking: return "Still this?"
        case .editing(.smaller, _): return "What part of it, right now?"
        case .editing(.newAnchor, _): return "What are you doing instead?"
        }
    }
}

private struct OnboardingPermissionView: View {
    @ObservedObject var model: OverlayFlowModel
    let snapshotMode: Bool

    var body: some View {
        OverlayBackdrop(heavy: false, snapshotMode: snapshotMode) {
            VStack(alignment: .leading, spacing: 22) {
                Text("Accessibility")
                    .font(.largeTitle)
                    .fontWeight(.medium)
                Text("Anchr reads the text of the front window. It takes no pictures.")
                    .foregroundStyle(.white.opacity(0.48))
                HStack(spacing: 10) {
                    Button("Open System Settings") { AccessibilityPermission.openSystemSettings() }
                    Button("Continue") { model.continueFromPermission() }
                }
                .buttonStyle(.bordered)
                status(model.statusMessage)
                Text("1 / 3")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.24))
            }
            .frame(width: 560, alignment: .leading)
        }
    }
}

private struct OnboardingKeyView: View {
    @ObservedObject var model: OverlayFlowModel
    let snapshotMode: Bool

    var body: some View {
        OverlayBackdrop(heavy: false, snapshotMode: snapshotMode) {
            VStack(alignment: .leading, spacing: 22) {
                Text("Connect OpenRouter")
                    .font(.largeTitle)
                    .fontWeight(.medium)
                    .accessibilityIdentifier("onboardingKeyTitle")
                Text("Anchr sends the text of the front window to one small model to judge it. Copy an API key from openrouter.ai/keys, then press Check.")
                    .foregroundStyle(.white.opacity(0.48))
                Button(model.isCheckingKey ? "Checking…" : "Check key") {
                    Task { await model.verifyOpenRouter() }
                }
                .buttonStyle(.bordered)
                .disabled(model.isCheckingKey)
                .accessibilityIdentifier("onboardingKeyCheckButton")
                status(model.statusMessage)
                Text("2 / 3")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.24))
            }
            .frame(width: 560, alignment: .leading)
        }
    }
}

private func header(_ title: String, meta: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
        Text(title)
        Spacer()
        Text(meta)
            .font(.caption.monospaced())
            .tracking(0.6)
            .foregroundStyle(.white.opacity(0.24))
    }
    .padding(.bottom, 14)
    .overlay(alignment: .bottom) { Divider().overlay(.white.opacity(0.12)) }
}

private func hints(_ values: [String]) -> some View {
    HStack(spacing: 22) {
        ForEach(values.filter { !$0.isEmpty }, id: \.self) { value in
            Text(value)
                .font(.caption2.monospaced())
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.24))
        }
        Spacer(minLength: 0)
    }
    .padding(.top, 14)
    .overlay(alignment: .top) { Divider().overlay(.white.opacity(0.07)) }
    .padding(.top, 26)
}

@ViewBuilder
private func status(_ value: String?) -> some View {
    if let value {
        Text(value)
            .font(.caption.monospaced())
            .foregroundStyle(.white.opacity(0.48))
    }
}

private struct FlowKeyEvent {
    let characters: String
    let keyCode: UInt16

    var switcherKey: SwitcherKey? {
        switch characters.lowercased() {
        case "\u{f700}", "w": return .moveUp
        case "\u{f701}", "s": return .moveDown
        case "\r": return .open
        case "c": return .editContext
        case "n": return .newList
        case "\u{1b}": return .escape
        default: return nil
        }
    }

    var interventionKey: InterventionKey? {
        switch characters {
        case "1", "\r": return .answerBack
        case "2": return .answerSmaller
        case "3": return .answerNewAnchor
        default: return nil
        }
    }
}

private struct FlowKeyCapture: NSViewRepresentable {
    let onKey: (FlowKeyEvent) -> Void

    func makeNSView(context: Context) -> FlowKeyNSView {
        let view = FlowKeyNSView()
        view.onKey = onKey
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: FlowKeyNSView, context: Context) {
        nsView.onKey = onKey
        DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
    }
}

private final class FlowKeyNSView: NSView {
    var onKey: ((FlowKeyEvent) -> Void)?
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard let characters = event.charactersIgnoringModifiers else { return }
        onKey?(FlowKeyEvent(characters: characters, keyCode: event.keyCode))
    }
}
