// The focus timer of the whole app: one per process (`AppServices
// .focusTimer`), so two Mac windows or two iPad scenes show the same
// pomodoro instead of each running its own and recording it twice.
//
// It keeps the `FocusTimer` (docs/apple.md §8), saves it in `key_values`
// after every change (`LocalSettings.setFocusTimer`) so a relaunch carries
// on, and while a pomodoro or a break runs looks at the clock every second:
// a stretch that has run out is recorded here (`EfficiencyRepo
// .saveFocusSession`), once, whichever windows are open. The screens only
// show `timer` and hand changes in with `update(_:)`.
//
//     services.focusTimer.update(t)        // after start / pause / abandon …
//     services.focusTimer.timer            // what to show
//     services.focusTimer.onStretchEnded   // the UI's end sound

import Foundation
import Observation
import OpenTodoDomain

@MainActor @Observable
public final class FocusTimerStore {
    public private(set) var timer: FocusTimer

    @ObservationIgnored private let settings: LocalSettings
    @ObservationIgnored private let repo: EfficiencyRepo
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private var ticker: Task<Void, Never>?
    /// Books (nil: cancels) the notification for the end of what runs.
    /// Tests replace it.
    @ObservationIgnored public var scheduleEnd: @MainActor (Date?, String) -> Void = { FocusEndNotifier.schedule($0, $1) }
    /// Called when a pomodoro or a break runs out (the UI plays a sound).
    @ObservationIgnored public var onStretchEnded: (@MainActor () -> Void)?
    /// A recorded session that couldn't be written.
    @ObservationIgnored public var onError: (@MainActor (any Error) -> Void)?
    /// How often a running timer is looked at.
    @ObservationIgnored private let interval: Duration

    public init(settings: LocalSettings, repo: EfficiencyRepo, clock: @escaping @Sendable () -> Date = { Date() },
                interval: Duration = .seconds(1)) {
        self.settings = settings
        self.repo = repo
        self.clock = clock
        self.interval = interval
        var t = settings.focusTimer ?? FocusTimer(settings: settings.focusSettings)
        if t.phase == .idle { t.settings = settings.focusSettings }
        timer = t
        catchUp()
        runTicker()
    }

    public var nowMillis: Int { Int((clock().timeIntervalSince1970 * 1000).rounded()) }

    /// The timer after something the person did: kept, saved, its end
    /// booked. Sessions the change produced (an abandon, a stopwatch's end)
    /// are the caller's to save.
    public func update(_ t: FocusTimer) {
        guard t != timer else { return }
        timer = t
        settings.setFocusTimer(t)
        bookEnd()
        runTicker()
    }

    /// New lengths: saved, and taken by the timer at once if it's idle
    /// (otherwise from its next start).
    public func setSettings(_ s: FocusSettings) {
        settings.setFocusSettings(s)
        if timer.phase == .idle {
            var t = timer
            t.settings = s
            update(t)
        }
    }

    /// Records whatever ran out by now, each session once. Returns them.
    @discardableResult
    public func catchUp() -> [FocusSession] {
        var t = timer
        let recorded = t.tick(at: nowMillis)
        guard !recorded.isEmpty else { return [] }
        timer = t
        settings.setFocusTimer(t)
        let repo = self.repo
        let report = onError
        Task {
            for s in recorded {
                do { try await repo.saveFocusSession(s) } catch { report?(error) }
            }
        }
        onStretchEnded?()
        bookEnd()
        return recorded
    }

    /// Books the notification for the end of what's running, or cancels it.
    public func bookEnd() {
        let end = timer.endsAt(at: nowMillis).map { Date(timeIntervalSince1970: Double($0) / 1000) }
        scheduleEnd(end, focusEndMessage(timer))
    }

    private func runTicker() {
        guard timer.isRunning, ticker == nil else { return }
        let interval = self.interval
        ticker = Task { [weak self] in
            while let self, self.timer.isRunning, !Task.isCancelled {
                try? await Task.sleep(for: interval)
                self.catchUp()
            }
            self?.ticker = nil
        }
    }
}

/// The notification's text for the end of what `t` is running.
public func focusEndMessage(_ t: FocusTimer) -> String {
    switch t.phase {
    case .resting: "休息结束，开始下一个番茄吧"
    default: t.mode == .pomodoro ? "番茄完成了，休息一下吧" : "专注结束"
    }
}
