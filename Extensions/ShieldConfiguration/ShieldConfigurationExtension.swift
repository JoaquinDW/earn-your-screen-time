import EarnDomain
import ManagedSettings
import ManagedSettingsUI
import OSLog
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private let logger = Logger(subsystem: "EarnYourScreenTime", category: "Shield")
    /// The v6 night palette, restated in `UIColor` because the extension cannot import the app's
    /// design system. Keep these in step with `Night` in `App/DesignSystem/NightTheme.swift` —
    /// this is the one surface where the two have to be maintained by hand.
    private enum Palette {
        /// `Night.ground` — #070E0D.
        static let background = UIColor(red: 7 / 255, green: 14 / 255, blue: 13 / 255, alpha: 1)
        /// `Night.text` — #ECF3EE.
        static let paper = UIColor(red: 236 / 255, green: 243 / 255, blue: 238 / 255, alpha: 1)
        /// `Night.cobalt` — #2E5CE6.
        static let cobalt = UIColor(red: 46 / 255, green: 92 / 255, blue: 230 / 255, alpha: 1)
        /// `Night.textMuted` — #93A79D.
        static let secondary = UIColor(red: 147 / 255, green: 167 / 255, blue: 157 / 255, alpha: 1)
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
        let viewModel = ShieldViewModel(sharedState: SharedStore.shared.load(now: now), now: now)
        let copy = copy(for: viewModel)
        logger.notice(
            "event=screen_time_session_prompt_shown state=\(viewModel.state.rawValue, privacy: .public) available_minutes=\(viewModel.availableMinutes) steps_remaining=\(viewModel.stepsRemaining)"
        )

        return ShieldConfiguration(
            backgroundBlurStyle: nil,
            backgroundColor: Palette.background,
            icon: UIImage(named: "app-logo"),
            title: .init(text: copy.title, color: Palette.paper),
            subtitle: .init(text: copy.subtitle, color: Palette.secondary),
            primaryButtonLabel: .init(
                text: primaryButtonTitle(for: viewModel),
                color: Palette.paper
            ),
            primaryButtonBackgroundColor: Palette.cobalt,
            secondaryButtonLabel: secondaryButtonTitle(for: viewModel).map {
                .init(text: $0, color: Palette.secondary)
            }
        )
    }

    private func copy(for viewModel: ShieldViewModel) -> (title: String, subtitle: String) {
        guard AppGroup.isConfigured else {
            return (localized("shield.noTime.title"), localized("shield.noTime.subtitle"))
        }
        guard viewModel.hasActivityData || viewModel.availableMinutes > 0 else {
            return (localized("shield.updating.title"), localized("shield.updating.subtitle"))
        }

        switch viewModel.state {
        case .rewardAvailable:
            return (
                formatted("shield.available.title", viewModel.availableMinutes),
                localized("shield.available.subtitle")
            )
        case .sessionExpired:
            return (
                formatted(
                    "shield.expired.title",
                    viewModel.sessionDurationMinutes ?? viewModel.consumedMinutesToday
                ),
                formatted("shield.expired.subtitle", viewModel.targetSteps)
            )
        case .almostThere:
            return (
                formatted("shield.almost.title", viewModel.stepsRemaining),
                formatted(
                    "shield.almost.subtitle",
                    viewModel.rewardMinutes,
                    viewModel.estimatedWalkMinutes
                )
            )
        case .dailyGoalCompleted:
            return (
                localized("shield.goal.title"),
                formatted(
                    "shield.goal.subtitle",
                    viewModel.currentSteps,
                    viewModel.earnedMinutesToday
                )
            )
        case .noTime, .progress:
            return (
                localized("shield.noTime.title"),
                formatted(
                    "shield.noTime.progress",
                    viewModel.stepsRemaining,
                    viewModel.rewardMinutes,
                    viewModel.estimatedWalkMinutes
                )
            )
        }
    }

    private func primaryButtonTitle(for viewModel: ShieldViewModel) -> String {
        guard #available(iOS 26.5, *) else { return localized("shield.action.close") }
        switch viewModel.state {
        case .rewardAvailable:
            return localized("shield.action.chooseTime")
        default:
            return localized("shield.action.openEarn")
        }
    }

    private func secondaryButtonTitle(for viewModel: ShieldViewModel) -> String? {
        guard #available(iOS 26.5, *), viewModel.state == .rewardAvailable else { return nil }
        return localized("shield.action.notNow")
    }

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, bundle: localizationBundle, comment: "")
    }

    private func formatted(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: localized(key),
            locale: AppLanguage.saved.locale,
            arguments: arguments
        )
    }

    private var localizationBundle: Bundle {
        let resource: String
        switch AppLanguage.saved {
        case .system:
            return .main
        case .english:
            resource = "en"
        case .spanish:
            resource = "es"
        }

        guard let path = Bundle.main.path(forResource: resource, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}
