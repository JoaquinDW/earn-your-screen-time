import SwiftUI

enum PushupsLocalization {
    static let tableName = "PushupsLocalizable"

    static func string(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: tableName)
    }
}

struct PushupsText: View {
    private let key: LocalizedStringKey

    init(_ key: LocalizedStringKey) {
        self.key = key
    }

    var body: some View {
        Text(key, tableName: PushupsLocalization.tableName)
    }
}
