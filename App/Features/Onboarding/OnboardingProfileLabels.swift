import EarnDomain
import SwiftUI

// The display names for the onboarding profile's answer bands.
//
// These outlived the multi-question step they were written for: v6's onboarding asks two
// of the same questions inline, so the labels stay and the step that held them is gone.

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
