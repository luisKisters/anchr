import Foundation
import AnchrKit

@MainActor
public protocol ObservationClock: AnyObject {
    var now: Date { get }
}

@MainActor
public final class SystemObservationClock: ObservationClock {
    public init() {}
    public var now: Date { Date() }
}

@MainActor
public final class ObservationLoop {
    public typealias InterventionHandler = (Verdict) throws -> Void

    private let clock: any ObservationClock
    private let focusSource: any FocusContextSource
    private let snapshotter: any ObservationSnapshotting
    private let classifier: any DriftClassifier
    private let store: ListStore
    private let onIntervention: InterventionHandler

    private var context: FocusContext?
    private var schedulerEvents: [CheckScheduler.Event] = []
    private var policyEvents: [InterventionPolicy.Event] = []
    private var lastCall: Date?
    private var isStarted = false

    public init(
        clock: any ObservationClock,
        focusSource: any FocusContextSource,
        snapshotter: any ObservationSnapshotting,
        classifier: any DriftClassifier,
        store: ListStore,
        onIntervention: @escaping InterventionHandler
    ) {
        self.clock = clock
        self.focusSource = focusSource
        self.snapshotter = snapshotter
        self.classifier = classifier
        self.store = store
        self.onIntervention = onIntervention
    }

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        focusSource.start { [weak self] context in
            self?.focusDidChange(context)
        }
    }

    public func stop() {
        guard isStarted else { return }
        focusSource.stop()
        isStarted = false
    }

    public func recordUserInput() {
        schedulerEvents.append(.userInput(at: clock.now))
    }

    public func recordScreenLock(isLocked: Bool) {
        schedulerEvents.append(.screenLockChanged(isLocked: isLocked, at: clock.now))
    }

    public func recordAnchrFrontmost(isFrontmost: Bool) {
        schedulerEvents.append(.anchrFrontmostChanged(isFrontmost: isFrontmost, at: clock.now))
    }

    @discardableResult
    public func checkIfDue() async throws -> Verdict? {
        let now = clock.now
        guard let context,
              CheckScheduler.shouldCheck(events: schedulerEvents, now: now, lastCall: lastCall)
        else { return nil }

        let snapshot = try snapshotter.snapshotForCheck(
            processIdentifier: context.processIdentifier
        )
        let observation = try makeObservation(context: context, snapshot: snapshot)

        lastCall = now
        let verdict = try await classifier.classify(observation)
        policyEvents.append(.verdict(verdict.verdict, at: now))
        if InterventionPolicy.shouldIntervene(events: policyEvents, now: now) {
            try onIntervention(verdict)
            policyEvents.append(.intervention(at: now))
        }
        return verdict
    }

    private func focusDidChange(_ context: FocusContext) {
        self.context = context
        schedulerEvents.append(.focusChanged(at: clock.now))
        try? snapshotter.applicationDidBecomeFrontmost(
            processIdentifier: context.processIdentifier
        )
    }

    private func makeObservation(
        context: FocusContext,
        snapshot: AXSnapshotResult?
    ) throws -> Observation {
        let state = try store.loadState()
        guard let slug = state.activeListSlug else { throw ListStoreError.noActiveList }
        guard let anchorIndex = state.anchorIndex else { throw ListStoreError.noAnchor }
        let list = try store.loadList(slug: slug)
        guard let anchor = Anchor(index: anchorIndex, in: list) else {
            throw AnchorError.invalidIndex
        }

        var contextLines = ["App: \(context.bundleIdentifier)"]
        if let title = context.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            contextLines.append("Window: \(title)")
        }
        if let snapshot,
           snapshot.usefulCharacterCount > 0 {
            let boundedText = String(snapshot.text.prefix(AXSnapshotWalker.defaultMaximumCharacters))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !boundedText.isEmpty {
                contextLines.append(boundedText)
            }
        }

        return Observation(
            anchor: list.items[anchorIndex].text,
            parentChain: anchor.parentItems(in: list).map(\.text),
            projectContext: try store.loadContext(slug: slug),
            openItems: list.items.filter { !$0.done }.map(\.text),
            accessibilityText: contextLines.joined(separator: "\n")
        )
    }
}
