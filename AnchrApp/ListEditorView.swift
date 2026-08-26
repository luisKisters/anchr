import AnchrCore
import AnchrKit
import AppKit
import SwiftUI

@MainActor
final class ListEditorModel: ObservableObject {
    @Published private(set) var state: ListEditorState
    let listName: String

    private let store: ListStore?
    private let slug: String?

    init(store: ListStore = ListStore(rootURL: AppSupportRoot.url)) {
        self.store = store

        if let appState = try? store.loadState(),
           let slug = appState.activeListSlug,
           let list = try? store.loadList(slug: slug)
        {
            self.slug = slug
            listName = slug.replacingOccurrences(of: "-", with: " ")
            state = ListEditorState(
                list: list,
                selection: appState.anchorIndex ?? 0,
                anchorIndex: appState.anchorIndex
            )
        } else {
            slug = nil
            listName = "No list"
            state = ListEditorState(list: TodoList(items: []), selection: nil, anchorIndex: nil)
        }
    }

    init(previewState: ListEditorState, listName: String) {
        state = previewState
        self.listName = listName
        store = nil
        slug = nil
    }

    func send(_ key: ListEditorKey) {
        let previous = state
        state = ListEditor.reduce(state, key: key)
        guard previous.list != state.list || previous.anchorIndex != state.anchorIndex else { return }
        persist()
    }

    private func persist() {
        guard let store, let slug else { return }
        try? store.saveList(state.list, slug: slug)
        guard var appState = try? store.loadState() else { return }
        appState.anchorIndex = state.anchorIndex
        try? store.saveState(appState)
    }
}

struct ListEditorView: View {
    @ObservedObject var model: ListEditorModel
    let onClose: () -> Void
    let onSwitcher: () -> Void
    let snapshotMode: Bool
    @FocusState private var focusedEditor: Int?

    init(
        model: ListEditorModel,
        snapshotMode: Bool = false,
        onClose: @escaping () -> Void,
        onSwitcher: @escaping () -> Void = {}
    ) {
        self.model = model
        self.snapshotMode = snapshotMode
        self.onClose = onClose
        self.onSwitcher = onSwitcher
    }

    var body: some View {
        ZStack {
            if snapshotMode {
                Rectangle().fill(.black).ignoresSafeArea()
            } else {
                Rectangle()
                    .fill(.black.opacity(0.34))
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()
            }

            sheet
                .frame(width: 720)
        }
        .foregroundStyle(.white)
        .background {
            KeyCaptureView(isEnabled: !model.state.isEditing) { key in
                model.send(key)
                if model.state.shouldClose {
                    onClose()
                }
                if model.state.shouldOpenSwitcher {
                    onSwitcher()
                }
            }
        }
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.listName)
                    .font(.body)
                Spacer()
                Text("\(doneCount) / \(model.state.list.items.count)  ·  ⌘K TO SWITCH")
                    .font(.caption.monospaced())
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.24))
            }
            .padding(.bottom, 14)
            .overlay(alignment: .bottom) {
                Divider().overlay(.white.opacity(0.12))
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("ANCHOR")
                    .font(.caption2.monospaced())
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.24))
                Text(anchorText)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.48))
                Spacer()
            }
            .padding(.top, 14)
            .padding(.bottom, 18)

            Group {
                if snapshotMode {
                    listRows
                } else {
                    ScrollView {
                        listRows
                    }
                }
            }
            .frame(maxHeight: 520)

            keyHints
                .padding(.top, 14)
                .overlay(alignment: .top) {
                    Divider().overlay(.white.opacity(0.07))
                }
                .padding(.top, 26)
        }
    }

    private var listRows: some View {
        VStack(spacing: 0) {
            ForEach(model.state.list.items.indices, id: \.self) { index in
                row(model.state.list.items[index], at: index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func row(_ item: Item, at index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            checkbox(done: item.done)
                .padding(.top, 3)
                .accessibilityElement()
                .accessibilityIdentifier("listCheckbox_\(index)_\(item.done ? "done" : "open")")

            if model.state.selection == index, let editingText = model.state.editingText {
                TextField(
                    "",
                    text: Binding(
                        get: { editingText },
                        set: { model.send(.replaceEditingText($0)) }
                    )
                )
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($focusedEditor, equals: index)
                .onSubmit { model.send(.enter) }
                .onExitCommand { model.send(.escape) }
                .onKeyPress(keys: [.tab]) { press in
                    model.send(press.modifiers.contains(.shift) ? .unindent : .indent)
                    return .handled
                }
                .task { focusedEditor = index }
            } else {
                Text(item.text)
                    .font(.callout)
                    .foregroundStyle(item.done ? .white.opacity(0.24) : .white.opacity(0.86))
                    .strikethrough(item.done)
                    .accessibilityIdentifier("listItem_\(index)")
            }

            Spacer(minLength: 8)
            if model.state.anchorIndex == index {
                Text("ANCHOR")
                    .font(.caption2.monospaced())
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.24))
            }
        }
        .padding(.vertical, 7)
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .background {
            if model.state.selection == index {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.white.opacity(0.07))
            }
        }
        .overlay(alignment: .leading) {
            if model.state.selection == index {
                Rectangle().fill(.white).frame(width: 2)
            }
        }
        .padding(.leading, CGFloat(item.depth) * 26)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            model.state.selection == index ? "listRow_selected" : "listRow_\(index)"
        )
        .contentShape(Rectangle())
        .onTapGesture { model.send(.select(index)) }
    }

    private func checkbox(done: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .stroke(.white.opacity(done ? 1 : 0.42), lineWidth: 1)
            if done {
                RoundedRectangle(cornerRadius: 2).fill(.white)
            }
        }
        .frame(width: 13, height: 13)
    }

    private var keyHints: some View {
        HStack(spacing: 22) {
            if model.state.isEditing {
                hint("↵  SAVE")
                hint("ESC  CANCEL")
                hint("EMPTY + ↵  DELETES")
            } else {
                hint("↑↓ / WS  MOVE")
                hint("SPACE  DONE")
                hint("↵  EDIT")
                hint("⇥  INDENT")
                hint("N  NEW")
                hint("A  SET ANCHOR")
                hint("ESC  CLOSE")
            }
            Spacer(minLength: 0)
        }
    }

    private func hint(_ value: String) -> some View {
        Text(value)
            .font(.caption2.monospaced())
            .tracking(0.6)
            .foregroundStyle(.white.opacity(0.24))
    }

    private var doneCount: Int {
        model.state.list.items.filter(\.done).count
    }

    private var anchorText: String {
        guard let anchorIndex = model.state.anchorIndex,
              model.state.list.items.indices.contains(anchorIndex)
        else { return "—" }
        return model.state.list.items[anchorIndex].text
    }
}

private struct KeyCaptureView: NSViewRepresentable {
    let isEnabled: Bool
    let onKey: (ListEditorKey) -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.isEnabled = isEnabled
        view.onKey = onKey
        if isEnabled {
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.onKey = onKey
        if isEnabled, nsView.window?.firstResponder !== nsView {
            DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
        }
    }
}

private final class KeyCaptureNSView: NSView {
    var isEnabled = true
    var onKey: ((ListEditorKey) -> Void)?

    override var acceptsFirstResponder: Bool { isEnabled }

    override func keyDown(with event: NSEvent) {
        guard let key = Self.editorKey(for: event) else {
            super.keyDown(with: event)
            return
        }
        onKey?(key)
    }

    private static func editorKey(for event: NSEvent) -> ListEditorKey? {
        if event.keyCode == 48 {
            return event.modifierFlags.contains(.shift) ? .unindent : .indent
        }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "k" {
            return .openSwitcher
        }
        return switch event.charactersIgnoringModifiers?.lowercased() {
        case "\u{f700}", "w": .moveUp
        case "\u{f701}", "s": .moveDown
        case " ": .toggleDone
        case "\r": .enter
        case "n": .newItem
        case "a": .setAnchor
        case "\u{1b}": .escape
        default: nil
        }
    }
}
