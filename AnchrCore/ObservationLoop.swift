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
    private var lastSkipReason: String?
    private var lastFingerprint: Int?
    private var lastVerdict: Verdict.Kind?

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

    /// What the person did with the last interruption. "Back to it" changes nothing about
    /// the list, so it must not buy the same quiet as actually changing the task.
    public func recordInterventionAnswer(_ answer: InterventionPolicy.Answer) {
        policyEvents.append(.answered(answer, at: clock.now))
        Log.write("intervention answered=\(answer)")
    }

    public func recordAnchrFrontmost(isFrontmost: Bool) {
        schedulerEvents.append(.anchrFrontmostChanged(isFrontmost: isFrontmost, at: clock.now))
    }

    @discardableResult
    public func checkIfDue() async throws -> Verdict? {
        let now = clock.now
        guard let context else {
            logSkip("no focus context yet (accessibility observer never fired)")
            return nil
        }
        // Reading the screen is local and free, so it happens before the decision that
        // costs money. The text itself is what tells us whether anything is worth judging.
        guard CheckScheduler.shouldSample(events: schedulerEvents, now: now, lastCall: lastCall)
        else {
            logSkip("not due")
            return nil
        }

        let snapshot = try snapshotter.snapshotForCheck(
            processIdentifier: context.processIdentifier
        )
        let observation = try makeObservation(context: context, snapshot: snapshot)

        let fingerprint = observation.accessibilityText.hashValue
        let contentChanged = fingerprint != lastFingerprint
        guard let reason = CheckScheduler.shouldCall(
            events: schedulerEvents,
            now: now,
            lastCall: lastCall,
            contentChanged: contentChanged,
            isSuspicious: lastVerdict == .offTask
        ) else {
            logSkip("screen unchanged in \(context.bundleIdentifier)")
            return nil
        }

        Log.write(
            "check reason=\(reason.rawValue) app=\(context.bundleIdentifier) "
                + "axChars=\(observation.accessibilityText.count) anchor=\(observation.anchor)"
        )

        lastSkipReason = nil
        lastFingerprint = fingerprint
        lastCall = now
        let verdict = try await classifier.classify(observation)
        lastVerdict = verdict.verdict
        policyEvents.append(.verdict(verdict.verdict, at: now))
        let intervenes = InterventionPolicy.shouldIntervene(events: policyEvents, now: now)
        Log.write("verdict=\(verdict.verdict) intervene=\(intervenes) evidence=\(verdict.evidence)")
        if intervenes {
            try onIntervention(verdict)
            policyEvents.append(.intervention(at: now))
        }
        return verdict
    }

    /// Skips are the normal case — logging every one would bury the interesting lines, so
    /// only a changed reason is written.
    private func logSkip(_ reason: String) {
        guard reason != lastSkipReason else { return }
        lastSkipReason = reason
        Log.write("skip \(reason)")
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
        if let url = context.url, !url.isEmpty {
            contextLines.append("URL: \(url)")
        }
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
