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
        // The editor always keeps one line to hold the caret, and that line starts empty.
        // The file should not.
        let saved = TodoList(items: state.list.items.filter { !$0.text.isEmpty })
        try? store.saveList(saved, slug: slug)
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
        // A fallback for the moment there is no line to type in — an empty list has no
        // text field, and Escape still has to get you out of the window.
        .onExitCommand { send(.escape) }
    }

    private func send(_ key: ListEditorKey) {
        model.send(key)
        if model.state.shouldClose {
            onClose()
        }
        if model.state.shouldOpenSwitcher {
            onSwitcher()
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

            if model.state.selection == index {
                LineEditor(
                    text: item.text,
                    isDone: item.done,
                    onText: { send(.replaceText($0)) },
                    onKey: { send($0) }
                )
                .accessibilityIdentifier("listItem_\(index)")
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
            hint("↵  NEW LINE")
            hint("⇥ / ⇧⇥  INDENT")
            hint("⌘↵  SET ANCHOR")
            hint("⌘D  DONE")
            hint("⌘K  SWITCH")
            hint("ESC  CLOSE")
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



/// The line you are typing in, as a real `NSTextField`.
///
/// SwiftUI could not do this job. `@FocusState` did not reliably take focus when the
/// selection moved, so after Return the caret was nowhere and no key reached the app until
/// you clicked. And Tab never arrived at `.onKeyPress`: AppKit spends it on focus
/// navigation before SwiftUI sees it, so Shift-Tab could not outdent. AppKit solves both
/// directly — `doCommandBy` gets the tab keys by name, and first responder is
/// something you can simply set.
private struct LineEditor: NSViewRepresentable {
    let text: String
    let isDone: Bool
    let onText: (String) -> Void
    let onKey: (ListEditorKey) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onText: onText, onKey: onKey)
    }

    func makeNSView(context: Context) -> CommandTextField {
        let field = CommandTextField()
        field.wantsFocus = true
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .preferredFont(forTextStyle: .body)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.stringValue = text
        field.onCommand = { context.coordinator.onKey($0) }
        return field
    }

    func updateNSView(_ field: CommandTextField, context: Context) {
        context.coordinator.onText = onText
        context.coordinator.onKey = onKey
        field.onCommand = { context.coordinator.onKey($0) }
        if field.stringValue != text {
            field.stringValue = text
        }
        field.textColor = NSColor.white.withAlphaComponent(isDone ? 0.24 : 0.86)

        field.takeFocusIfNeeded()
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var onText: (String) -> Void
        var onKey: (ListEditorKey) -> Void

        init(onText: @escaping (String) -> Void, onKey: @escaping (ListEditorKey) -> Void) {
            self.onText = onText
            self.onKey = onKey
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            onText(field.stringValue)
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy selector: Selector
        ) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                onKey(.newLine)
            case #selector(NSResponder.insertTab(_:)):
                onKey(.indent)
            case #selector(NSResponder.insertBacktab(_:)):
                onKey(.unindent)
            case #selector(NSResponder.moveUp(_:)):
                onKey(.moveUp)
            case #selector(NSResponder.moveDown(_:)):
                onKey(.moveDown)
            case #selector(NSResponder.cancelOperation(_:)):
                onKey(.escape)
            case #selector(NSResponder.deleteBackward(_:)):
                // Only when there is nothing left to delete; otherwise the field keeps its
                // own character handling.
                guard control.stringValue.isEmpty else { return false }
                onKey(.deleteBackward)
            default:
                return false
            }
            return true
        }
    }
}

/// Command shortcuts have to be caught before the field editor turns them into text
/// editing commands, which is what `performKeyEquivalent` is for.
private final class CommandTextField: NSTextField {
    var onCommand: ((ListEditorKey) -> Void)?

    /// Set once, for the lifetime of the view: this field is only ever built for the
    /// selected line.
    var wantsFocus = false

    /// Moving the selection destroys one of these views and builds another, and the new
    /// one is not in a window yet when SwiftUI first updates it. Asking for first responder
    /// at that moment silently does nothing — which is why pressing Return created the new
    /// line but left the caret behind, and nothing typed afterwards arrived anywhere.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        takeFocusIfNeeded()
    }

    func takeFocusIfNeeded() {
        guard wantsFocus, let window else { return }
        if let editor = currentEditor(), window.firstResponder === editor { return }

        // Synchronously where possible. Every asynchronous hop is a window in which the
        // overlay is on screen with nothing focused, and a keystroke in that gap goes to
        // the application underneath instead.
        if window.makeFirstResponder(self) {
            placeCaretAtEnd()
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                if window.makeFirstResponder(self) { self.placeCaretAtEnd() }
            }
        }
    }

    /// `makeFirstResponder` selects the whole field, so switching lines armed Backspace to
    /// wipe the task you just moved to. The caret belongs after the last character, the way
    /// it would in any editor.
    private func placeCaretAtEnd() {
        guard let editor = currentEditor() else { return }
        let end = (stringValue as NSString).length
        editor.selectedRange = NSRange(location: end, length: 0)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "\r":
            onCommand?(.setAnchor)
        case "d":
            onCommand?(.toggleDone)
        case "k":
            onCommand?(.openSwitcher)
        default:
            return super.performKeyEquivalent(with: event)
        }
        return true
    }
}
