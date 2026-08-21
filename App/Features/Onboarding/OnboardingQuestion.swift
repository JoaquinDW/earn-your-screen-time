import EarnDomain
import SwiftUI

enum OnboardingQuestion: Int, CaseIterable, Identifiable {
    case scrolling, movement, outcomes

    var id: Int { rawValue }
    var number: Int { rawValue + 1 }
    static var count: Int { allCases.count }

    var title: LocalizedStringKey {
        switch self {
        case .scrolling: "onboarding.v2.question.scrolling.title"
        case .movement: "onboarding.v2.question.movement.title"
        case .outcomes: "onboarding.v2.question.outcomes.title"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .scrolling: "onboarding.v2.question.scrolling.subtitle"
        case .movement: "onboarding.v2.question.movement.subtitle"
        case .outcomes: "onboarding.v2.question.outcomes.subtitle"
        }
    }

    func options(for profile: Binding<OnboardingProfile>) -> [Answer] {
        switch self {
        case .scrolling:
            OnboardingProfile.ScrollingBand.allCases.map { value in
                Answer(key: value.rawValue, label: value.label,
                       isSelected: profile.wrappedValue.scrolling == value) {
                    profile.wrappedValue.scrolling = value
                }
            }
        case .movement:
            OnboardingProfile.MovementBand.allCases.map { value in
                Answer(key: value.rawValue, label: value.label,
                       isSelected: profile.wrappedValue.movement == value) {
                    profile.wrappedValue.movement = value
                }
            }
        case .outcomes:
            OnboardingProfile.DesiredOutcome.allCases.map { value in
                Answer(key: value.rawValue, label: value.label,
                       isSelected: profile.wrappedValue.desiredOutcomes.contains(value)) {
                    if profile.wrappedValue.desiredOutcomes.contains(value) {
                        profile.wrappedValue.desiredOutcomes.remove(value)
                    } else {
                        profile.wrappedValue.desiredOutcomes.insert(value)
                    }
                }
            }
        }
    }

    func isAnswered(in profile: OnboardingProfile) -> Bool {
        switch self {
        case .scrolling: profile.scrolling != nil
        case .movement: profile.movement != nil
        case .outcomes: !profile.desiredOutcomes.isEmpty
        }
    }

    struct Answer: Identifiable {
        let key: String
        let label: LocalizedStringKey
        let isSelected: Bool
        let select: () -> Void
        var id: String { key }
    }
}

extension OnboardingProfile.DesiredOutcome {
    var label: LocalizedStringKey {
        switch self {
        case .walkMore: "onboarding.v2.outcome.walkMore"
        case .scrollLess: "onboarding.v2.outcome.scrollLess"
        case .feelInControl: "onboarding.v2.outcome.control"
        case .beMoreActive: "onboarding.v2.outcome.active"
        case .beMoreIntentional: "onboarding.v2.outcome.intentional"
        case .stopLosingHours: "onboarding.v2.outcome.hours"
        }
    }
}

extension OnboardingProfile.ScrollingBand {
    var label: LocalizedStringKey {
        switch self {
        case .underOneHour: "onboarding.v2.scrolling.underOne"
        case .oneToTwoHours: "onboarding.v2.scrolling.oneToTwo"
        case .twoToThreeHours, .threeToFourHours: "onboarding.v2.scrolling.twoToFour"
        case .fourHoursPlus: "onboarding.v2.scrolling.fourPlus"
        }
    }
}

extension OnboardingProfile.MovementBand {
    var label: LocalizedStringKey {
        switch self {
        case .underThreeThousand: "onboarding.v2.movement.underThree"
        case .threeToFiveThousand: "onboarding.v2.movement.threeToFive"
        case .fiveToEightThousand: "onboarding.v2.movement.fiveToEight"
        case .eightThousandPlus: "onboarding.v2.movement.eightPlus"
        case .unsure: "onboarding.v2.movement.unsure"
        }
    }
}
