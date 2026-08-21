import DeviceActivity
import EarnDomain
import FamilyControls
import Foundation
import OSLog

/// Carries one explicit access session in a non-repeating DeviceActivity schedule.
struct MonitorScheduler {
    static let shared = MonitorScheduler()
    private static let legacyActivityName = DeviceActivityName("earnYourScreenTimeDaily")
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
    }

    private var center: DeviceActivityCenter { DeviceActivityCenter() }
    private var defaults: UserDefaults { AppGroup.defaults }

    /// Keeps a valid registration, or recreates it for the session's remaining wall-clock time.
    func refresh(
        state: SharedState,
        selection: FamilyActivitySelection,
        now: Date = Date()
    ) throws {
        guard !selection.isEmpty,
              let session = state.activeSession(at: now),
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

        // Starting one second in the past guarantees that `now` falls inside the interval. The
        // carrier ends 15 minutes from now; warningTime targets the session's actual `endsAt`.
        let calendar = Calendar.current
        let intervalStart = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: now.addingTimeInterval(-1)
        )
        let intervalEnd = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: now.addingTimeInterval(TimeInterval(SessionMonitorPlan.carrierSeconds))
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
