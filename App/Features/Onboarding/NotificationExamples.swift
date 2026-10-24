import SwiftUI

/// The notifications Earnit actually sends, drawn as Lock Screen banners.
///
/// Shown before the permission prompt so the person decides on these three messages rather than
/// on the word "notifications". Each one names a number they will recognise from their own plan.
struct NotificationExamples: View {
    let stepsPerReward: Int
    let rewardMinutes: Int
    let dailyGoal: Int
    /// The banner for the daily reminder shows the time the person is choosing under it.
    let reminderTime: Date

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            NotificationBanner(
                time: Text("now"),
                title: Text("+\(rewardMinutes) min earned"),
                message: Text("\(stepsPerReward.formatted()) steps done. You have \(rewardMinutes) min ready for your apps.")
            )
            NotificationBanner(
                time: Text(reminderTime, style: .time),
                title: Text("\((dailyGoal / 4).formatted()) steps to today's goal"),
                message: Text("Finish it for +10 bonus min. A short walk does it.")
            )
            .opacity(0.86)
            NotificationBanner(
                time: Text("now"),
                title: Text("session.notification.warning.title"),
                message: Text("session.notification.warning.body")
            )
            .opacity(0.7)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Examples of Earnit notifications")
    }
}

private struct NotificationBanner: View {
    let time: Text
    let title: Text
    let message: Text

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            Image("app-logo")
                .resizable()
                .scaledToFill()
                .frame(width: 38, height: 38)
                .clipShape(.rect(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(verbatim: "Earnit")
                        .font(.sans(12, weight: .semibold))
                        .foregroundStyle(Night.textSoft)
                    Spacer()
                    time
                        .font(.sans(12))
                        .foregroundStyle(Night.textMuted)
                }
                title
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(Night.text)
                message
                    .font(.sans(13.5))
                    .foregroundStyle(Night.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Space.s + 2)
        .background(Night.panel, in: .rect(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(Night.edge) }
        .accessibilityElement(children: .combine)
    }
}
