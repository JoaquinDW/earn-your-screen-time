import EarnDomain
import ManagedSettings
import ManagedSettingsUI
import OSLog
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private let logger = Logger(subsystem: "EarnYourScreenTime", category: "Shield")
    private enum Palette {
        static let background = UIColor(red: 41 / 255, green: 40 / 255, blue: 36 / 255, alpha: 1)
        static let paper = UIColor(red: 250 / 255, green: 248 / 255, blue: 244 / 255, alpha: 1)
        static let cobalt = UIColor(red: 30 / 255, green: 77 / 255, blue: 247 / 255, alpha: 1)
        static let secondary = UIColor(red: 205 / 255, green: 206 / 255, blue: 211 / 255, alpha: 1)
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
            "event=shield_displayed state=\(viewModel.state.rawValue, privacy: .public) available_minutes=\(viewModel.availableMinutes) steps_remaining=\(viewModel.stepsRemaining)"
        )

        return ShieldConfiguration(
            backgroundBlurStyle: .systemMaterialDark,
            backgroundColor: Palette.background,
            icon: guardianImage,
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
        case .sessionExpired:
            return (
                formatted("shield.expired.title", viewModel.sessionDurationMinutes ?? 0),
                formatted("shield.expired.subtitle", viewModel.stepsRemaining)
            )
        case .rewardAvailable:
            return (
                formatted("shield.available.title", viewModel.availableMinutes),
                localized("shield.available.subtitle")
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
        case .sessionExpired:
            return localized("shield.action.earnMore")
        default:
            return localized("shield.action.openEarn")
        }
    }

    private func secondaryButtonTitle(for viewModel: ShieldViewModel) -> String? {
        guard #available(iOS 26.5, *), viewModel.state == .rewardAvailable else { return nil }
        return localized("shield.action.notNow")
    }

    private var guardianImage: UIImage? {
        UIImage(named: "guardian-resting")
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
