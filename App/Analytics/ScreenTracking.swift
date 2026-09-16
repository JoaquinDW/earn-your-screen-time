import SwiftUI

extension View {
    func trackScreen(_ name: String, analytics: any AnalyticsTracking) -> some View {
        onAppear { analytics.track(.screenViewed(name)) }
    }
}
