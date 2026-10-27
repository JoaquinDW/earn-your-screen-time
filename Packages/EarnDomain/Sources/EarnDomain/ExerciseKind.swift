import Foundation

/// A camera-counted exercise the server rewards. Raw values match the backend's `exercise_type`.
public enum ExerciseKind: String, Codable, CaseIterable, Sendable {
    case pushup
    case squat
    case jumpingJack = "jumping_jack"
    /// Alternating lunges, one repetition per leg.
    case lunge

    public var earningMethod: EarningMethod {
        switch self {
        case .pushup: .pushups
        case .squat: .squats
        case .jumpingJack: .jumpingJacks
        case .lunge: .lunges
        }
    }
}
