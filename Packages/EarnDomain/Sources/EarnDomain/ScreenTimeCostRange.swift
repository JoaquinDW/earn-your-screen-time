/// The time represented by a self-reported daily scrolling category.
public struct ScreenTimeCostRange: Equatable, Sendable {
    public struct Bounds: Equatable, Sendable {
        public let lowerBound: Double
        /// Nil means the range has no known upper bound.
        public let upperBound: Double?

        public init(lowerBound: Double, upperBound: Double?) {
            self.lowerBound = lowerBound
            self.upperBound = upperBound
        }
    }

    public let weeklyHours: Bounds
    public let annualDays: Bounds

    public init(scrollingBand: OnboardingProfile.ScrollingBand) {
        let dailyHours: Bounds
        switch scrollingBand {
        case .underOneHour:
            dailyHours = Bounds(lowerBound: 0, upperBound: 1)
        case .oneToTwoHours:
            dailyHours = Bounds(lowerBound: 1, upperBound: 2)
        case .twoToThreeHours, .threeToFourHours:
            dailyHours = Bounds(lowerBound: 2, upperBound: 4)
        case .fourHoursPlus:
            dailyHours = Bounds(lowerBound: 4, upperBound: nil)
        }

        weeklyHours = Bounds(
            lowerBound: dailyHours.lowerBound * 7,
            upperBound: dailyHours.upperBound.map { $0 * 7 }
        )
        annualDays = Bounds(
            lowerBound: dailyHours.lowerBound * 365 / 24,
            upperBound: dailyHours.upperBound.map { $0 * 365 / 24 }
        )
    }
}
