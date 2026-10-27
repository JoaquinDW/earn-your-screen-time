import EarnDomain
import SwiftUI

/// Friends and squads: the people who notice when you skip a day.
///
/// BePresent messages your buddy when you miss your goal; Jomo groups friends into squads.
/// Earnit shares one small summary per day (movement goal, steps, minutes earned, streak) and
/// nothing about which apps are protected or how minutes were spent.
struct FriendsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.locale) private var locale

    @State private var model = FriendsModel()
    @State private var name = ""
    @State private var codeEntry = ""
    @State private var squadName = ""
    @State private var isAddingFriend = false
    @State private var isJoiningSquad = false
    @State private var isCreatingSquad = false
    @State private var friendToRemove: SocialFriend?
    @State private var isConfirmingLeave = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                VStack(alignment: .leading, spacing: 6) {
                    NightEyebrow(text: "friends.eyebrow")
                    Text("friends.title")
                        .font(.serif(38, relativeTo: .largeTitle))
                        .accessibilityAddTraits(.isHeader)
                }

                if let message = model.message {
                    Text(message)
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(Night.textSoft)
                        .padding(Theme.Space.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Night.cobaltWash, in: .rect(cornerRadius: Night.panelRadius))
                }

                switch model.phase {
                case .loading:
                    ProgressView()
                        .tint(Night.textSoft)
                        .frame(maxWidth: .infinity, minHeight: 200)
                case .unavailable:
                    unavailable
                case .setup:
                    setup
                case .ready:
                    ready
                }
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.top, Theme.Space.l)
            .padding(.bottom, Theme.Space.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .foregroundStyle(Night.text)
        .background(Night.ground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Night.ground, for: .navigationBar)
        .refreshable { await model.load(in: env) }
        .task {
            await model.load(in: env)
            await model.markEventsRead(in: env)
        }
        .alert("friends.add.title", isPresented: $isAddingFriend) {
            TextField("friends.code.placeholder", text: $codeEntry)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("friends.add.confirm") {
                let code = codeEntry
                Task { await model.addFriend(code: code, in: env) }
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("friends.add.message")
        }
        .alert("friends.squad.join.title", isPresented: $isJoiningSquad) {
            TextField("friends.code.placeholder", text: $codeEntry)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("friends.squad.join.confirm") {
                let code = codeEntry
                Task { await model.joinSquad(code: code, in: env) }
            }
            Button("common.cancel", role: .cancel) {}
        }
        .alert("friends.squad.create.title", isPresented: $isCreatingSquad) {
            TextField("friends.squad.create.placeholder", text: $squadName)
            Button("friends.squad.create.confirm") {
                let name = squadName
                Task { await model.createSquad(name: name, in: env) }
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("friends.squad.create.message")
        }
        .confirmationDialog(
            "friends.remove.title",
            isPresented: Binding(get: { friendToRemove != nil }, set: { if !$0 { friendToRemove = nil } }),
            titleVisibility: .visible,
            presenting: friendToRemove
        ) { friend in
            Button("friends.remove.confirm", role: .destructive) {
                Task { await model.remove(friend, in: env) }
            }
        } message: { friend in
            Text("friends.remove.message \(friend.displayName)")
        }
        .confirmationDialog("friends.leave.title", isPresented: $isConfirmingLeave, titleVisibility: .visible) {
            Button("friends.leave.confirm", role: .destructive) {
                Task { await model.leave(in: env) }
            }
        } message: {
            Text("friends.leave.message")
        }
        .trackScreen("friends", analytics: env.analytics)
    }

    // MARK: - States

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("friends.unavailable")
                .font(.sans(15))
                .foregroundStyle(Night.textSoft)
                .fixedSize(horizontal: false, vertical: true)
            Button("friends.retry") {
                Task { await model.load(in: env) }
            }
            .buttonStyle(.nightPill)
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text("friends.setup.lead")
                .font(.sans(16))
                .foregroundStyle(Night.textSoft)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                bullet("figure.walk", "friends.setup.shares")
                bullet("hand.raised", "friends.setup.misses")
                bullet("lock", "friends.setup.private")
            }

            TextField("friends.setup.namePlaceholder", text: $name)
                .textContentType(.givenName)
                .font(.sans(17, weight: .medium))
                .padding(Theme.Space.m)
                .background(Night.panel, in: .rect(cornerRadius: Night.panelRadius))

            Button {
                let chosen = name.trimmingCharacters(in: .whitespacesAndNewlines)
                Task { await model.createProfile(name: chosen, in: env) }
            } label: {
                Text("friends.setup.start").frame(maxWidth: .infinity)
            }
            .buttonStyle(.nightPill)
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isWorking)
        }
    }

    @ViewBuilder
    private var ready: some View {
        if !model.overview.events.isEmpty {
            inbox
        }
        friendsSection
        squadsSection
        if let profile = model.overview.profile {
            settingsSection(profile)
        }
    }

    // MARK: - Inbox

    private var inbox: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            NightEyebrow(text: "friends.inbox")
            VStack(spacing: 0) {
                ForEach(model.overview.events.prefix(5)) { event in
                    HStack(spacing: 12) {
                        Image(systemName: icon(for: event.kind))
                            .font(.sans(13, weight: .semibold))
                            .foregroundStyle(event.kind == .missedGoal ? Night.textSoft : Night.moss)
                            .frame(width: 22)
                            .accessibilityHidden(true)
                        eventText(event)
                            .font(.sans(14, weight: event.isRead ? .regular : .semibold))
                            .foregroundStyle(event.isRead ? Night.textMuted : Night.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    if event.id != model.overview.events.prefix(5).last?.id {
                        NightHairline(inset: 34)
                    }
                }
            }
        }
    }

    private func icon(for kind: SocialEvent.Kind) -> String {
        switch kind {
        case .missedGoal: "moon.zzz"
        case .nudge: "hand.point.right"
        case .cheer: "hands.clap"
        case .friendAdded: "person.badge.plus"
        }
    }

    private func eventText(_ event: SocialEvent) -> Text {
        switch event.kind {
        case .missedGoal: Text("friends.event.missedGoal \(event.actorName)")
        case .nudge: Text("friends.event.nudge \(event.actorName)")
        case .cheer: Text("friends.event.cheer \(event.actorName)")
        case .friendAdded: Text("friends.event.friendAdded \(event.actorName)")
        }
    }

    // MARK: - Friends

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            NightEyebrow(text: "friends.list")
            if model.overview.friends.isEmpty {
                Text("friends.list.empty")
                    .font(.sans(14))
                    .foregroundStyle(Night.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.overview.friends) { friend in
                        friendRow(friend)
                        if friend.id != model.overview.friends.last?.id {
                            NightHairline()
                        }
                    }
                }
            }
            inviteActions
        }
    }

    private func friendRow(_ friend: SocialFriend) -> some View {
        let metGoal = friend.today?.goalMet == true
        let kind: SocialSendKind = metGoal ? .cheer : .nudge
        let alreadySent = metGoal ? friend.cheeredToday : friend.nudgedToday

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: friend.displayName)
                        .font(.sans(16, weight: .semibold))
                    if let streak = friend.today?.streakDays ?? friend.yesterday?.streakDays, streak > 1 {
                        Label {
                            Text(verbatim: "\(streak)")
                        } icon: {
                            Image(systemName: "flame.fill")
                        }
                        .font(.sans(12, weight: .semibold))
                        .foregroundStyle(Night.moss)
                        .labelStyle(.titleAndIcon)
                    }
                }
                status(for: friend)
                    .font(.sans(12.5))
                    .foregroundStyle(friend.missedYesterday ? Night.textSoft : Night.textMuted)
            }
            Spacer(minLength: Theme.Space.s)
            Button {
                Task { await model.send(kind, to: friend, in: env) }
            } label: {
                Image(systemName: alreadySent ? "checkmark" : (metGoal ? "hands.clap.fill" : "hand.point.right.fill"))
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(alreadySent ? Night.textMuted : Night.cobaltText)
                    .frame(width: Theme.minTouchTarget, height: Theme.minTouchTarget)
                    .background(Night.cobaltWash.opacity(alreadySent ? 0.4 : 1), in: .circle)
            }
            .buttonStyle(.plain)
            .disabled(alreadySent || model.isWorking)
            .accessibilityLabel(Text(metGoal ? LocalizedStringKey("friends.cheer") : LocalizedStringKey("friends.nudge")))
        }
        .padding(.vertical, 12)
        .contextMenu {
            Button("friends.remove", systemImage: "person.badge.minus", role: .destructive) {
                friendToRemove = friend
            }
        }
    }

    private func status(for friend: SocialFriend) -> Text {
        if friend.missedYesterday {
            return Text("friends.status.missedYesterday")
        }
        guard let today = friend.today else {
            return Text("friends.status.noUpdate")
        }
        let steps = today.activityAmount.formatted(.number.locale(locale))
        if today.goalMet {
            return Text("friends.status.goalMet \(steps)")
        }
        let goal = today.dailyGoal.formatted(.number.locale(locale))
        return Text("friends.status.progress \(steps) \(goal)")
    }

    private var inviteActions: some View {
        HStack(spacing: Theme.Space.s) {
            if let profile = model.overview.profile {
                ShareLink(
                    item: AppConfiguration.appStoreURL,
                    message: Text("friends.invite.message \(profile.inviteCode) \(AppConfiguration.appStoreURL.absoluteString)")
                ) {
                    Label("friends.invite", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.nightPill)
                .simultaneousGesture(TapGesture().onEnded {
                    env.analytics.track(.friendInviteShared.withProperties(["kind": .string("friend")]))
                })
            }
            Button {
                codeEntry = ""
                isAddingFriend = true
            } label: {
                Image(systemName: "number")
                    .font(.sans(16, weight: .semibold))
                    .frame(width: 56, height: 56)
                    .background(Night.panel, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("friends.add.title"))
        }
        .padding(.top, Theme.Space.s)
    }

    // MARK: - Squads

    private var squadsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 3) {
                NightEyebrow(text: "friends.squads")
                Text("friends.squads.subtitle")
                    .font(.sans(12.5))
                    .foregroundStyle(Night.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(model.overview.squads) { squad in
                squadCard(squad)
            }
            HStack(spacing: Theme.Space.s) {
                Button("friends.squad.create") {
                    squadName = ""
                    isCreatingSquad = true
                }
                Button("friends.squad.join") {
                    codeEntry = ""
                    isJoiningSquad = true
                }
            }
            .buttonStyle(.quiet)
            .disabled(model.isWorking)
        }
    }

    private func squadCard(_ squad: SocialSquad) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: squad.name)
                    .font(.serif(24))
                Spacer()
                ShareLink(
                    item: AppConfiguration.appStoreURL,
                    message: Text("friends.squad.invite.message \(squad.name) \(squad.inviteCode) \(AppConfiguration.appStoreURL.absoluteString)")
                ) {
                    Label {
                        Text(verbatim: squad.inviteCode)
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .font(.sans(12.5, weight: .semibold))
                    .foregroundStyle(Night.cobaltText)
                }
                .simultaneousGesture(TapGesture().onEnded {
                    env.analytics.track(.friendInviteShared.withProperties(["kind": .string("squad")]))
                })
            }
            NightEyebrow(text: "friends.squad.week", color: Night.textFaint)
            ForEach(Array(squad.standings.enumerated()), id: \.element.id) { index, standing in
                HStack(spacing: 10) {
                    Text(verbatim: "\(index + 1)")
                        .font(.sans(13, weight: .bold))
                        .foregroundStyle(index == 0 ? Night.moss : Night.textMuted)
                        .frame(width: 18, alignment: .leading)
                        .monospacedDigit()
                    Text(verbatim: standing.displayName)
                        .font(.sans(14, weight: standing.userId == model.overview.profile?.userId ? .bold : .medium))
                        .lineLimit(1)
                    Spacer(minLength: Theme.Space.s)
                    Text("friends.squad.goalDays \(standing.goalDays)")
                        .font(.sans(12.5, weight: .semibold))
                        .foregroundStyle(Night.textSoft)
                    Text(ImpactFormat.duration(standing.earnedSeconds, locale: locale))
                        .font(.sans(12.5))
                        .foregroundStyle(Night.textMuted)
                        .frame(minWidth: 52, alignment: .trailing)
                        .monospacedDigit()
                }
                .frame(minHeight: 32)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(Theme.Space.m)
        .background(Night.panel, in: .rect(cornerRadius: Night.panelRadius))
        .contextMenu {
            Button("friends.squad.leave", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                Task { await model.leave(squad, in: env) }
            }
        }
    }

    // MARK: - Settings

    private func settingsSection(_ profile: SocialProfile) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            NightEyebrow(text: "friends.settings")
            Toggle(isOn: Binding(
                get: { profile.shareMisses },
                set: { share in Task { await model.setShareMisses(share, in: env) } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("friends.settings.shareMisses")
                        .font(.sans(15, weight: .medium))
                    Text("friends.settings.shareMisses.footer")
                        .font(.sans(12))
                        .foregroundStyle(Night.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Night.cobalt)
            .disabled(model.isWorking)
            Text("friends.settings.name \(profile.displayName) \(profile.inviteCode)")
                .font(.sans(12.5))
                .foregroundStyle(Night.textMuted)
            Button("friends.leave", role: .destructive) { isConfirmingLeave = true }
                .buttonStyle(.quiet)
        }
    }

    private func bullet(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .font(.sans(13, weight: .semibold))
                .foregroundStyle(Night.moss)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(text)
                .font(.sans(14))
                .foregroundStyle(Night.textSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack {
        FriendsView()
    }
    .environment(AppEnvironment(
        screenTime: MockScreenTimeService(status: .approved),
        health: MockHealthKitService(hasRequested: true)
    ))
}
