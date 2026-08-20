import FamilyControls
import Foundation
import ManagedSettings

extension ManagedSettingsStore.Name {
    /// A named store so the app and its extensions write to the same set of restrictions.
    static let restricted = Self("earnYourScreenTimeRestricted")
}

/// Applies and removes the shields on the user's restricted apps.
struct ShieldController {
    static let shared = ShieldController()

    private var store: ManagedSettingsStore { ManagedSettingsStore(named: .restricted) }

    /// Shields everything the user selected. No selection means nothing to shield.
    func apply(_ selection: FamilyActivitySelection) {
        let store = self.store
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        store.shield.webDomainCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
    }

    /// Lets the selected apps be opened again.
    func clear() {
        let store = self.store
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        store.shield.webDomainCategories = nil
    }
}
