import EarnDomain
import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private enum Presentation {
        case sessionEnded
        case timeAvailable(minutes: Int)
        case moreStepsNeeded(steps: Int, rewardMinutes: Int)
        case genericLocked
    }

    private enum Palette {
        static let background = UIColor(red: 36 / 255, green: 33 / 255, blue: 30 / 255, alpha: 1)
        static let paper = UIColor(red: 1, green: 250 / 255, blue: 242 / 255, alpha: 1)
        static let coral = UIColor(red: 217 / 255, green: 128 / 255, blue: 95 / 255, alpha: 1)
        static let coralLight = UIColor(red: 243 / 255, green: 214 / 255, blue: 200 / 255, alpha: 1)
    }

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        configuration()
    }

    override func configuration(
        shielding application: Application,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        configuration()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        configuration()
    }

    override func configuration(
        shielding webDomain: WebDomain,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        configuration()
    }

    private func configuration(now: Date = Date()) -> ShieldConfiguration {
        let copy = copy(for: presentation(now: now))
        let iconConfiguration = UIImage.SymbolConfiguration(pointSize: 52, weight: .medium)
        let icon = UIImage(systemName: "figure.walk", withConfiguration: iconConfiguration)?
            .withTintColor(Palette.coral, renderingMode: .alwaysOriginal)

        return ShieldConfiguration(
            backgroundBlurStyle: .systemMaterialDark,
            backgroundColor: Palette.background,
            icon: icon,
            title: .init(text: copy.title, color: Palette.paper),
            subtitle: .init(text: copy.subtitle, color: Palette.coralLight),
            primaryButtonLabel: .init(text: primaryButtonTitle, color: Palette.background),
            primaryButtonBackgroundColor: Palette.coral
        )
    }

    private func presentation(now: Date) -> Presentation {
        guard AppGroup.isConfigured else { return .genericLocked }

        let state = SharedStore.shared.load(now: now)
        if let session = state.currentSession {
            let secondsFromEnd = now.timeIntervalSince(session.endsAt)
            // The callback can arrive a few seconds around `endsAt`. This window only selects
            // copy; it never decides whether the app is shielded.
            if secondsFromEnd >= -5, secondsFromEnd <= 120 {
                return .sessionEnded
            }
        }

        let availableMinutes = state.ledger.wallet.availableMinutes
        if availableMinutes >= ScreenTimeSessionEngine.supportedDurations[0] {
            return .timeAvailable(minutes: availableMinutes)
        }

        let next = CreditEngine.nextMilestone(in: state.ledger)
        if state.ledger.rule.source == .steps, next.remainingAmount > 0 {
            return .moreStepsNeeded(
                steps: next.remainingAmount,
                rewardMinutes: next.rewardMinutes
            )
        }
        return .genericLocked
    }

    private func copy(for presentation: Presentation) -> (title: String, subtitle: String) {
        switch presentation {
        case .sessionEnded:
            return (
                localized("shield.sessionEnded.title"),
                localized("shield.sessionEnded.subtitle")
            )
        case let .timeAvailable(minutes):
            return (
                localized("shield.available.title"),
                formatted("shield.available.subtitle", minutes)
            )
        case let .moreStepsNeeded(steps, rewardMinutes):
            return (
                localized("shield.noTime.title"),
                formatted("shield.noTime.progress", steps, rewardMinutes)
            )
        case .genericLocked:
            return (
                localized("shield.noTime.title"),
                localized("shield.noTime.subtitle")
            )
        }
    }

    private var primaryButtonTitle: String {
        if #available(iOS 26.5, *) {
            localized("shield.action.openEarn")
        } else {
            localized("shield.action.close")
        }
    }

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, bundle: .main, comment: "")
    }

    private func formatted(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: localized(key),
            locale: Locale.current,
            arguments: arguments
        )
    }
}
