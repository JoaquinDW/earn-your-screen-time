import EarnDomain
import SwiftUI

/// When the protected apps are shielded, and the promise not to loosen that for a while.
///
/// Opal, one sec and BePresent all let people block only during work or at night, and all of
/// them sell a mode that cannot be switched off early. Without a schedule Earnit shields around
/// the clock, which is a lot to ask of someone who only struggles in the evening.
struct BlockingPolicyView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var isScheduled = false
    @State private var start = BlockingPolicyView.time(hour: 9)
    @State private var end = BlockingPolicyView.time(hour: 18)
    @State private var weekdays: Set<Int> = BlockSchedule.workdays
    @State private var pendingStrictEnd: Date?
    @State private var isShowingPaywall = false

    var body: some View {
        Form {
            Group {
                scheduleSection
                if scheduleHasChanges {
                    saveSection
                }
                strictModeSection
            }
            .listRowBackground(Night.panel)
        }
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, Theme.Space.xxl, for: .scrollContent)
        .background(Night.ground.ignoresSafeArea())
        .settingsSurface()
        .tint(Night.cobalt)
        .navigationTitle("blocking.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Night.ground, for: .navigationBar)
        .onAppear(perform: loadSchedule)
        .confirmationDialog(
            "strictMode.confirm.title",
            isPresented: strictConfirmationBinding,
            titleVisibility: .visible,
            presenting: pendingStrictEnd
        ) { end in
            Button("strictMode.confirm.apply") {
                env.startStrictMode(until: end)
            }
            Button("common.cancel", role: .cancel) {}
        } message: { end in
            Text("strictMode.confirm.message \(formatted(end))")
        }
        .fullScreenCover(isPresented: $isShowingPaywall) {
            ProPaywallView(source: .settings)
        }
        .trackScreen("blocking_policy", analytics: env.analytics)
    }

    // MARK: - Schedule

    private var scheduleSection: some View {
        Section {
            Toggle("blocking.schedule.toggle", isOn: $isScheduled.animation())
            if isScheduled {
                DatePicker("blocking.schedule.start", selection: $start, displayedComponents: .hourAndMinute)
                DatePicker("blocking.schedule.end", selection: $end, displayedComponents: .hourAndMinute)
                weekdayPicker
            }
        } header: {
            header("blocking.schedule.section")
        } footer: {
            if isScheduled, editedSchedule == nil {
                Text("blocking.schedule.invalid")
            } else if isScheduled {
                Text("blocking.schedule.footer")
            } else {
                Text("blocking.schedule.always")
            }
        }
    }

    /// One chip per weekday, in the order the person's calendar starts its week.
    private var weekdayPicker: some View {
        HStack(spacing: 6) {
            ForEach(orderedWeekdays, id: \.self) { weekday in
                let selected = weekdays.contains(weekday)
                Button {
                    if selected { weekdays.remove(weekday) } else { weekdays.insert(weekday) }
                } label: {
                    Text(calendar.veryShortStandaloneWeekdaySymbols[weekday - 1])
                        .font(.sans(13, weight: .semibold))
                        .foregroundStyle(selected ? Night.text : Night.textMuted)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(selected ? Night.cobaltWash : Night.forestLift.opacity(0.4), in: .circle)
                        .overlay {
                            Circle().strokeBorder(selected ? Night.cobaltText.opacity(0.5) : .clear, lineWidth: 1)
                        }
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(calendar.standaloneWeekdaySymbols[weekday - 1]))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private var saveSection: some View {
        Section {
            Button("blocking.schedule.save") { saveSchedule() }
                .disabled(isScheduled && editedSchedule == nil || !strictAllowsSchedule)
        } footer: {
            if !strictAllowsSchedule {
                Text("strictMode.locked.schedule")
            }
        }
    }

    // MARK: - Strict mode

    private var strictModeSection: some View {
        Section {
            if let endsAt = env.strictModeEndsAt {
                LabeledContent("strictMode.activeUntil", value: formatted(endsAt))
            }
            Menu {
                ForEach(strictOptions, id: \.id) { option in
                    Button(option.label) { requestStrictMode(until: option.end) }
                }
            } label: {
                Text(env.isStrictModeActive ? LocalizedStringKey("strictMode.extend") : LocalizedStringKey("strictMode.start"))
            }
        } header: {
            header("strictMode.section")
        } footer: {
            Text("strictMode.footer")
        }
    }

    private struct StrictOption {
        let id: String
        let label: LocalizedStringKey
        let end: Date
    }

    private var strictOptions: [StrictOption] {
        let now = Date()
        var options: [StrictOption] = []
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
           midnight.timeIntervalSince(now) >= 3_600 {
            options.append(StrictOption(id: "midnight", label: "strictMode.option.midnight", end: midnight))
        }
        options.append(StrictOption(id: "day", label: "strictMode.option.day", end: now.addingTimeInterval(24 * 3_600)))
        options.append(StrictOption(id: "three_days", label: "strictMode.option.threeDays", end: now.addingTimeInterval(3 * 24 * 3_600)))
        options.append(StrictOption(id: "max", label: "strictMode.option.max", end: now.addingTimeInterval(StrictMode.maximumDuration)))
        return options
    }

    private func requestStrictMode(until end: Date) {
        guard env.subscriptionManager.isPro else {
            isShowingPaywall = true
            return
        }
        pendingStrictEnd = end
    }

    private var strictConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingStrictEnd != nil },
            set: { if !$0 { pendingStrictEnd = nil } }
        )
    }

    // MARK: - State

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = env.appLanguage.locale
        return calendar
    }

    private var orderedWeekdays: [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    private var editedSchedule: BlockSchedule? {
        BlockSchedule(startMinute: Self.minute(of: start), endMinute: Self.minute(of: end), weekdays: weekdays)
    }

    private var scheduleHasChanges: Bool {
        isScheduled ? editedSchedule != env.blockSchedule : env.blockSchedule != nil
    }

    private var strictAllowsSchedule: Bool {
        !env.isStrictModeActive
            || StrictMode.allowsScheduleChange(from: env.blockSchedule, to: isScheduled ? editedSchedule : nil)
    }

    private func loadSchedule() {
        guard let schedule = env.blockSchedule else {
            isScheduled = false
            return
        }
        isScheduled = true
        start = Self.time(minute: schedule.startMinute)
        end = Self.time(minute: schedule.endMinute)
        weekdays = schedule.weekdays
    }

    private func saveSchedule() {
        // Going back to around the clock is never behind the paywall.
        guard env.subscriptionManager.isPro || !isScheduled else {
            isShowingPaywall = true
            return
        }
        if isScheduled {
            guard let editedSchedule else { return }
            env.setBlockSchedule(editedSchedule)
        } else {
            env.setBlockSchedule(nil)
        }
        loadSchedule()
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).hour().minute().locale(env.appLanguage.locale))
    }

    private func header(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.sans(11, weight: .medium))
            .textCase(.uppercase)
            .kerning(1.9)
            .foregroundStyle(Night.textMuted)
            .padding(.bottom, 2)
    }

    private static func minute(of date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private static func time(hour: Int = 0, minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour + minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
    }
}

#Preview {
    NavigationStack {
        BlockingPolicyView()
    }
    .environment(AppEnvironment(
        screenTime: MockScreenTimeService(status: .approved),
        health: MockHealthKitService(hasRequested: true)
    ))
}
