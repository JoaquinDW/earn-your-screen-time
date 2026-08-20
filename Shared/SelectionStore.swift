import FamilyControls
import Foundation

/// Persists the user's chosen apps/categories/domains.
///
/// The tokens inside `FamilyActivitySelection` are opaque, privacy-preserving values that are
/// only meaningful to this app on this device — we store them as-is and never try to resolve
/// them to real app identities (PRD §27).
struct SelectionStore {
    static let shared = SelectionStore()

    private enum Key {
        static let selection = "shared.selection.v1"
    }

    private var defaults: UserDefaults { AppGroup.defaults }

    func load() -> FamilyActivitySelection {
        guard
            let data = defaults.data(forKey: Key.selection),
            let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else {
            return FamilyActivitySelection()
        }
        return selection
    }

    func save(_ selection: FamilyActivitySelection) {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: Key.selection)
    }

    func clear() {
        defaults.removeObject(forKey: Key.selection)
    }
}

extension FamilyActivitySelection {
    /// How many things the user picked, across apps, categories and web domains.
    var itemCount: Int {
        applicationTokens.count + categoryTokens.count + webDomainTokens.count
    }

    var isEmpty: Bool { itemCount == 0 }
}
