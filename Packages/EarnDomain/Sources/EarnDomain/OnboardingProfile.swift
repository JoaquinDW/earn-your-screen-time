import Foundation

/// The answers and recommendation produced by outcome-driven onboarding.
public struct OnboardingProfile: Codable, Equatable, Sendable {
    public var desiredOutcomes: Set<DesiredOutcome> {
        didSet { refreshRecommendationIfPossible() }
    }
    public var scrolling: ScrollingBand?
    public var movement: MovementBand? {
        didSet { refreshRecommendationIfPossible() }
    }
    /// Persisted so a future change to recommendation rules does not silently change an existing goal.
    public var recommendedDailyStepGoal: Int?

    public init(
        desiredOutcomes: Set<DesiredOutcome>,
        scrolling: ScrollingBand? = nil,
        movement: MovementBand? = nil,
        recommendedDailyStepGoal: Int? = nil
    ) {
        self.desiredOutcomes = desiredOutcomes
        self.scrolling = scrolling
        self.movement = movement
        self.recommendedDailyStepGoal = recommendedDailyStepGoal
            ?? movement.map { Self.recommendDailyStepGoal(movement: $0, outcomes: desiredOutcomes) }
    }

    public var isComplete: Bool {
        !desiredOutcomes.isEmpty && scrolling != nil && movement != nil && recommendedDailyStepGoal != nil
    }

    public var currentDailySteps: Int { (movement ?? .unsure).typicalSteps }
    public var dailyStepGoal: Int { recommendedDailyStepGoal ?? 8_000 }

    public static func recommendDailyStepGoal(
        movement: MovementBand,
        outcomes: Set<DesiredOutcome>
    ) -> Int {
        let base = movement.baseDailyStepGoal
        guard outcomes.contains(.walkMore) || outcomes.contains(.beMoreActive) else { return base }
        switch base {
        case ..<8_000: return 8_000
        default: return 10_000
        }
    }

    private mutating func refreshRecommendationIfPossible() {
        guard let movement else { return }
        recommendedDailyStepGoal = Self.recommendDailyStepGoal(movement: movement, outcomes: desiredOutcomes)
    }

    public enum DesiredOutcome: String, Codable, Sendable, CaseIterable {
        case walkMore
        case scrollLess
        case feelInControl
        case beMoreActive
        case beMoreIntentional
        case stopLosingHours
    }

    public enum ScrollingBand: String, Codable, Sendable, CaseIterable {
        case underOneHour
        case oneToTwoHours
        // Legacy case names remain real cases so the existing app's exhaustive switches compile.
        case twoToThreeHours
        case threeToFourHours
        case fourHoursPlus

        /// Canonical spelling for the new 2-4 hour band.
        public static var twoToFourHours: Self { .twoToThreeHours }

        public static var allCases: [Self] {
            [.underOneHour, .oneToTwoHours, .twoToFourHours, .fourHoursPlus]
        }

        private var persistedRawValue: String {
            switch self {
            case .twoToThreeHours, .threeToFourHours: "twoToFourHours"
            default: rawValue
            }
        }

        public init(from decoder: Decoder) throws {
            let rawValue = try decoder.singleValueContainer().decode(String.self)
            switch rawValue {
            case "underOneHour": self = .underOneHour
            case "oneToTwoHours": self = .oneToTwoHours
            case "twoToFourHours", "twoToThreeHours", "threeToFourHours": self = .twoToFourHours
            case "fourHoursPlus": self = .fourHoursPlus
            default:
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown scrolling band \(rawValue)"
                ))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(persistedRawValue)
        }
    }

    public enum MovementBand: String, Codable, Sendable, CaseIterable {
        case underThreeThousand
        case threeToFiveThousand
        case fiveToEightThousand
        case eightThousandPlus
        case unsure

        public var typicalSteps: Int {
            switch self {
            case .underThreeThousand: 2_000
            case .threeToFiveThousand: 4_000
            case .fiveToEightThousand: 6_500
            case .eightThousandPlus: 9_000
            case .unsure: 4_000
            }
        }

        public var baseDailyStepGoal: Int {
            switch self {
            case .underThreeThousand: 6_000
            case .threeToFiveThousand: 8_000
            case .fiveToEightThousand, .eightThousandPlus: 10_000
            case .unsure: 8_000
            }
        }
    }

    // MARK: - Legacy source compatibility

    public enum Goal: String, Codable, Sendable, CaseIterable {
        case walkMore, scrollLess, intentional, healthierHabits, everything
    }

    public enum WalkingBand: String, Codable, Sendable, CaseIterable {
        case underTwoFiveThousand
        case twoToFiveThousand
        case fiveToSevenFiveThousand
        case sevenFiveToTenThousand
        case tenThousandPlus

        public var typicalSteps: Int { movementBand.typicalSteps }

        fileprivate var movementBand: MovementBand {
            switch self {
            case .underTwoFiveThousand: .underThreeThousand
            case .twoToFiveThousand: .threeToFiveThousand
            case .fiveToSevenFiveThousand: .fiveToEightThousand
            case .sevenFiveToTenThousand, .tenThousandPlus: .eightThousandPlus
            }
        }
    }

    public enum StepTarget: String, Codable, Sendable, CaseIterable {
        case sixThousand, eightThousand, tenThousand, somethingElse

        public var dailySteps: Int {
            switch self {
            case .sixThousand: 6_000
            case .eightThousand: 8_000
            case .tenThousand: 10_000
            case .somethingElse: 9_000
            }
        }
    }

    public init(
        goal: Goal? = nil,
        scrolling: ScrollingBand? = nil,
        walking: WalkingBand? = nil,
        target: StepTarget? = nil
    ) {
        desiredOutcomes = Self.outcomes(for: goal)
        self.scrolling = scrolling
        movement = walking?.movementBand
        recommendedDailyStepGoal = target?.dailySteps
            ?? movement.map { Self.recommendDailyStepGoal(movement: $0, outcomes: desiredOutcomes) }
    }

    public var goal: Goal? {
        get {
            guard desiredOutcomes.count == 1, let outcome = desiredOutcomes.first else {
                return desiredOutcomes.isEmpty ? nil : .everything
            }
            switch outcome {
            case .walkMore: return .walkMore
            case .scrollLess: return .scrollLess
            case .beMoreIntentional: return .intentional
            case .beMoreActive: return .healthierHabits
            case .feelInControl, .stopLosingHours: return .everything
            }
        }
        set { desiredOutcomes = Self.outcomes(for: newValue) }
    }

    public var walking: WalkingBand? {
        get {
            switch movement {
            case .underThreeThousand: return .underTwoFiveThousand
            case .threeToFiveThousand: return .twoToFiveThousand
            case .fiveToEightThousand: return .fiveToSevenFiveThousand
            case .eightThousandPlus: return .tenThousandPlus
            case .unsure, nil: return nil
            }
        }
        set {
            movement = newValue?.movementBand
        }
    }

    public var target: StepTarget? {
        get {
            switch recommendedDailyStepGoal {
            case 6_000: return .sixThousand
            case 8_000: return .eightThousand
            case 10_000: return .tenThousand
            case .some: return .somethingElse
            case nil: return nil
            }
        }
        set { recommendedDailyStepGoal = newValue?.dailySteps }
    }

    private static func outcomes(for goal: Goal?) -> Set<DesiredOutcome> {
        switch goal {
        case .walkMore: [.walkMore]
        case .scrollLess: [.scrollLess]
        case .intentional: [.beMoreIntentional]
        case .healthierHabits: [.beMoreActive]
        case .everything: Set(DesiredOutcome.allCases)
        case nil: []
        }
    }

    // MARK: - Tolerant persistence

    private enum CodingKeys: String, CodingKey {
        case desiredOutcomes, scrolling, movement, recommendedDailyStepGoal
        case goal, walking, target
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyGoal = try? container.decode(Goal.self, forKey: .goal)
        desiredOutcomes = (try? container.decodeIfPresent(Set<DesiredOutcome>.self, forKey: .desiredOutcomes))
            ?? Self.outcomes(for: legacyGoal)
        scrolling = try? container.decodeIfPresent(ScrollingBand.self, forKey: .scrolling)
        movement = try? container.decodeIfPresent(MovementBand.self, forKey: .movement)
        if movement == nil, let oldWalking = try? container.decode(WalkingBand.self, forKey: .walking) {
            movement = oldWalking.movementBand
        }
        recommendedDailyStepGoal = try? container.decodeIfPresent(Int.self, forKey: .recommendedDailyStepGoal)
        if recommendedDailyStepGoal == nil,
           let oldTarget = try? container.decode(StepTarget.self, forKey: .target) {
            recommendedDailyStepGoal = oldTarget.dailySteps
        }
        if recommendedDailyStepGoal == nil, let movement {
            recommendedDailyStepGoal = Self.recommendDailyStepGoal(movement: movement, outcomes: desiredOutcomes)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(desiredOutcomes, forKey: .desiredOutcomes)
        try container.encodeIfPresent(scrolling, forKey: .scrolling)
        try container.encodeIfPresent(movement, forKey: .movement)
        try container.encodeIfPresent(recommendedDailyStepGoal, forKey: .recommendedDailyStepGoal)
    }
}
