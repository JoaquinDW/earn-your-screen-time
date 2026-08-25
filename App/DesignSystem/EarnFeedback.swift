import Foundation
import UIKit

enum EarnMotion {
    static let quick = 0.20
    static let standard = 0.32
    static let reward = 0.72
}

enum EarnHaptic: Equatable {
    case light
    case earned
    case unlocked
    case goalCompleted
    case warning
    case balanceExpired
    case error
}

/// The sole haptic boundary for the app. Presentation code publishes semantic events instead of
/// constructing UIKit generators directly, so the preference and throttling stay consistent.
@MainActor
enum HapticManager {
    static let preferenceKey = "haptic.feedback.enabled.v1"
    private static var lastTrigger: (haptic: EarnHaptic, date: Date)?
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let earnedImpact = UIImpactFeedbackGenerator(style: .soft)
    private static let unlockedImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let expiredImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let notification = UINotificationFeedbackGenerator()

    static var isEnabled: Bool {
        get {
            guard AppGroup.defaults.object(forKey: preferenceKey) != nil else { return true }
            return AppGroup.defaults.bool(forKey: preferenceKey)
        }
        set { AppGroup.defaults.set(newValue, forKey: preferenceKey) }
    }

    static func trigger(_ haptic: EarnHaptic) {
        guard isEnabled else { return }
        if let lastTrigger,
           lastTrigger.haptic == haptic,
           Date().timeIntervalSince(lastTrigger.date) < 0.35 {
            return
        }
        self.lastTrigger = (haptic, Date())

        switch haptic {
        case .light:
            lightImpact.impactOccurred(intensity: 0.7)
        case .earned:
            earnedImpact.impactOccurred(intensity: 0.85)
        case .unlocked:
            unlockedImpact.impactOccurred(intensity: 0.9)
        case .goalCompleted:
            notification.notificationOccurred(.success)
        case .warning:
            notification.notificationOccurred(.warning)
        case .balanceExpired:
            expiredImpact.impactOccurred(intensity: 0.75)
        case .error:
            notification.notificationOccurred(.error)
        }
    }

    /// Preparing before an asynchronous operation removes most first-use latency while the
    /// eventual haptic still fires only if that operation publishes a real domain transition.
    static func prepare(_ haptic: EarnHaptic) {
        guard isEnabled else { return }
        switch haptic {
        case .light: lightImpact.prepare()
        case .earned: earnedImpact.prepare()
        case .unlocked: unlockedImpact.prepare()
        case .balanceExpired: expiredImpact.prepare()
        case .goalCompleted, .warning, .error: notification.prepare()
        }
    }
}

enum EarnPresentationEvent: Equatable, Identifiable {
    case screenTimeEarned(minutes: Int)
    case firstRewardEarned(minutes: Int)
    case dailyGoalCompleted(minutes: Int)
    case appUnlocked
    case appLocked
    case balanceExpired
    case timeSaved(seconds: Int)
    case walletFull
    case streakUpdated(Int)
    case error

    var id: String {
        switch self {
        case let .screenTimeEarned(minutes): "earned-\(minutes)"
        case let .firstRewardEarned(minutes): "first-earned-\(minutes)"
        case let .dailyGoalCompleted(minutes): "goal-\(minutes)"
        case .appUnlocked: "unlocked"
        case .appLocked: "locked"
        case .balanceExpired: "expired"
        case let .timeSaved(seconds): "saved-\(seconds)"
        case .walletFull: "wallet-full"
        case let .streakUpdated(days): "streak-\(days)"
        case .error: "error"
        }
    }

    var haptic: EarnHaptic? {
        switch self {
        case .screenTimeEarned: .earned
        case .firstRewardEarned: .goalCompleted
        case .dailyGoalCompleted: .goalCompleted
        case .appUnlocked: .unlocked
        case .appLocked: nil
        case .balanceExpired: .balanceExpired
        case .timeSaved: .earned
        case .walletFull: .warning
        case .streakUpdated: .light
        case .error: .error
        }
    }
}

/// A short-lived, in-process event. Its identity changes even when two legitimate rewards have
/// the same amount, while its value stays easy for SwiftUI to render.
struct EarnPresentationFeedback: Identifiable, Equatable {
    let id = UUID()
    let event: EarnPresentationEvent
}
