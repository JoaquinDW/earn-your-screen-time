import DeviceActivity
import EarnDomain
import FamilyControls
import Foundation
import OSLog

/// Carries one explicit access session in a non-repeating DeviceActivity schedule, plus the two
/// policy activities: the daily blocking window and the end of strict mode.
struct MonitorScheduler {
    static let shared = MonitorScheduler()
    private static let legacyActivityName = DeviceActivityName("earnYourScreenTimeDaily")
    static let blockWindowActivityName = DeviceActivityName("earnitBlockWindow")
    static let strictModeActivityName = DeviceActivityName("earnitStrictMode")
    /// DeviceActivity refuses intervals shorter than this.
    private static let minimumIntervalSeconds: TimeInterval = 15 * 60

    /// Policy activities only ask for a reconcile; they never finish a session.
    static func isPolicyActivity(_ activity: DeviceActivityName) -> Bool {
        activity == blockWindowActivityName || activity == strictModeActivityName
    }
    private static let logger = Logger(
        subsystem: "com.balthasardeweert.earnyourscreentime",
        category: "DeviceActivityScheduler"
    )

    private struct Registration: Codable, Equatable {
        let sessionID: UUID
        let activityName: String
        let endsAt: Date
        let selection: Data
    }

    private enum Key {
        static let registration = "shared.sessionMonitorRegistration.v2"
        static let legacyRegistration = "shared.monitorRegistration.v1"
        static let blockWindow = "shared.blockWindowRegistration.v1"
        static let strictModeEnd = "shared.strictModeRegistration.v1"
    }

    private var center: DeviceActivityCenter { DeviceActivityCenter() }
    private var defaults: UserDefaults { AppGroup.defaults }

    /// Keeps a valid registration, or recreates it for the session's remaining wall-clock time.
    func refresh(
        state: SharedState,
        selection: FamilyActivitySelection,
        now: Date = Date()
    ) throws {
        guard let session = state.activeSession(at: now),
              let plan = SessionMonitorPlan.make(for: session, at: now) else {
            stopAll()
            return
        }

        let registration = Registration(
            sessionID: session.id,
            activityName: plan.activityName,
            endsAt: session.endsAt,
            selection: try JSONEncoder().encode(selection)
        )
        let activityName = DeviceActivityName(plan.activityName)
        if registration == storedRegistration, center.activities.contains(activityName) {
            Self.logger.debug("Keeping session monitor \(plan.activityName, privacy: .public)")
            return
        }

        stopAll()

        // Starting one second in the past guarantees that `now` falls inside the interval. Short
        // sessions use the 15-minute carrier; longer sessions end with the schedule itself.
        let calendar = Calendar.current
        let intervalStart = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: now.addingTimeInterval(-1)
        )
        let rawIntervalEnd = now.addingTimeInterval(TimeInterval(plan.scheduleSeconds))
        let roundedIntervalEnd = Date(
            timeIntervalSince1970: ceil(rawIntervalEnd.timeIntervalSince1970)
        )
        let intervalEnd = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: roundedIntervalEnd
        )
        let schedule = DeviceActivitySchedule(
            intervalStart: intervalStart,
            intervalEnd: intervalEnd,
            repeats: false,
            warningTime: plan.warningSeconds.map { DateComponents(second: $0) }
        )

        try center.startMonitoring(activityName, during: schedule)
        store(registration)
        Self.logger.notice(
            "Started session monitor \(plan.activityName, privacy: .public), remaining seconds: \(plan.remainingSeconds, privacy: .public)"
        )
    }

    func stop(sessionID: UUID) {
        center.stopMonitoring([DeviceActivityName(SessionMonitorPlan.activityName(for: sessionID))])
        if storedRegistration?.sessionID == sessionID {
            clearRegistration()
        }
    }

    func stopAll() {
        let sessionActivities = center.activities.filter {
            $0.rawValue.hasPrefix(SessionMonitorPlan.activityPrefix)
                || $0 == Self.legacyActivityName
        }
        if !sessionActivities.isEmpty {
            center.stopMonitoring(sessionActivities)
        }
        clearRegistration()
        defaults.removeObject(forKey: Key.legacyRegistration)
    }

    // MARK: - Policy

    /// Keeps the blocking window and the strict-mode end registered to match `state`. Session
    /// changes never touch these: `stopAll` only stops session activities.
    func refreshPolicy(state: SharedState, now: Date = Date()) throws {
        refreshStrictModeEnd(state.isStrictModeActive(at: now) ? state.strictModeUntil : nil, now: now)
        try refreshBlockWindow(state.blockSchedule)
    }

    /// One daily interval from the window's start to its end; DeviceActivity carries intervals
    /// across midnight. Weekdays are not part of the interval: every callback reconciles and
    /// `BlockSchedule.isBlocking` decides, so on a day off the callback finds nothing to shield.
    private func refreshBlockWindow(_ schedule: BlockSchedule?) throws {
        let name = Self.blockWindowActivityName
        guard let schedule else {
            if center.activities.contains(name) {
                center.stopMonitoring([name])
            }
            defaults.removeObject(forKey: Key.blockWindow)
            return
        }

        let stored = defaults.data(forKey: Key.blockWindow)
            .flatMap { try? JSONDecoder().decode(BlockSchedule.self, from: $0) }
        if stored == schedule, center.activities.contains(name) { return }

        center.stopMonitoring([name])
        let deviceSchedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: schedule.startMinute / 60, minute: schedule.startMinute % 60),
            intervalEnd: DateComponents(hour: schedule.endMinute / 60, minute: schedule.endMinute % 60),
            repeats: true
        )
        try center.startMonitoring(name, during: deviceSchedule)
        defaults.set(try JSONEncoder().encode(schedule), forKey: Key.blockWindow)
        Self.logger.notice("Started block window monitor")
    }

    /// A one-off interval ending when strict mode does, so the app-removal lock is lifted even if
    /// Earnit is never opened. Failing to register it is not fatal: the next reconcile after the
    /// end date lifts the lock too.
    private func refreshStrictModeEnd(_ end: Date?, now: Date) {
        let name = Self.strictModeActivityName
        guard let end else {
            if center.activities.contains(name) {
                center.stopMonitoring([name])
            }
            defaults.removeObject(forKey: Key.strictModeEnd)
            return
        }

        let stored = defaults.object(forKey: Key.strictModeEnd) as? Date
        if stored == end, center.activities.contains(name) { return }
        guard end.timeIntervalSince(now) >= Self.minimumIntervalSeconds else { return }

        center.stopMonitoring([name])
        let calendar = Calendar.current
        let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(components, from: now.addingTimeInterval(-1)),
            intervalEnd: calendar.dateComponents(components, from: end),
            repeats: false
        )
        do {
            try center.startMonitoring(name, during: schedule)
            defaults.set(end, forKey: Key.strictModeEnd)
        } catch {
            Self.logger.error("Could not monitor the end of strict mode: \(error.localizedDescription, privacy: .public)")
        }
    }

    var isMonitoring: Bool {
        center.activities.contains { $0.rawValue.hasPrefix(SessionMonitorPlan.activityPrefix) }
    }

    private var storedRegistration: Registration? {
        guard let data = defaults.data(forKey: Key.registration) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Registration.self, from: data)
    }

    private func store(_ registration: Registration) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(registration) else { return }
        defaults.set(data, forKey: Key.registration)
    }

    private func clearRegistration() {
        defaults.removeObject(forKey: Key.registration)
    }
}
