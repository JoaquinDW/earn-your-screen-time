import StoreKit
import SwiftUI

/// Onboarding until it is done, then the app's three top-level sections.
struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.requestReview) private var requestReview
    @State private var selectedSection: AppSection = .home
    @State private var isShowingDetail = false
    @State private var didStartSessionFromBlockedApp = false
    @State private var celebratedStreakDays = 0
    @AppStorage("streak.celebration.last-seen-day.v1") private var lastStreakCelebrationDay = ""

    var body: some View {
        ZStack {
            Group {
                if !env.hasCompletedOnboarding {
                    OnboardingView()
                } else if env.subscriptionManager.status == .unknown {
                    subscriptionLoading
                } else if env.requiresSubscription && !env.isUnlockPaywallDismissed {
                    // Closable: in 1.2.2 the only person to reach this paywall left the app
                    // from it, and a wall there also hid Settings, the way to unprotect apps.
                    // Spending minutes still needs Pro; every unlock surface offers it again.
                    ProPaywallView(source: .firstUnlock, onClose: env.dismissUnlockPaywall)
                } else {
                    mainContent
                }
            }

            if let feedback = env.presentationFeedback {
                EarnFeedbackOverlay(
                    feedback: feedback,
                    onFinished: { env.dismissPresentationFeedback(feedback) },
                    onImpact: { env.triggerPresentationFeedbackHaptic(feedback) },
                    shouldAnnounce: { env.shouldAnnouncePresentationFeedback(feedback) }
                )
                .zIndex(10)
            }

            if celebratedStreakDays > 0 {
                StreakCelebrationView(days: celebratedStreakDays, onDismiss: dismissStreakCelebration)
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        // v6 is one nocturnal palette, deliberately the same in both system appearances: the
        // illustrations are painted at dusk and there is no light variant of them to switch to.
        .preferredColorScheme(.dark)
        .tint(Night.cobalt)
        .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: env.hasCompletedOnboarding)
        .onAppear {
            applyPendingRoute(env.pendingRoute)
            if isAdaptiveIntroPending {
                env.setFeedbackPresentationSuspended(true, by: "root.adaptiveIntro")
            }
            if isPushupsIntroPending {
                env.setFeedbackPresentationSuspended(true, by: "root.pushupsIntro")
            }
            presentStreakCelebrationIfNeeded()
        }
        .onChange(of: env.pendingRoute) { _, route in
            applyPendingRoute(route)
        }
        .onChange(of: env.shouldRequestReview) { _, shouldRequest in
            guard shouldRequest else { return }
            requestReview()
            env.consumeReviewRequest()
        }
        .onChange(of: isAdaptiveIntroPending) { _, isPresented in
            guard isPresented else { return }
            env.setFeedbackPresentationSuspended(true, by: "root.adaptiveIntro")
        }
        .onChange(of: isPushupsIntroPending) { _, isPresented in
            guard isPresented else { return }
            env.setFeedbackPresentationSuspended(true, by: "root.pushupsIntro")
        }
        .onChange(of: streakCelebrationEligibilityToken) { _, _ in
            presentStreakCelebrationIfNeeded()
        }
        .fullScreenCover(isPresented: Binding(
            get: {
                env.hasCompletedOnboarding
                    && (!env.requiresSubscription || env.isUnlockPaywallDismissed)
                    && env.isPresentingBlockedAppDetail
            },
            set: { if !$0 { env.dismissBlockedAppDetail() } }
        ), onDismiss: {
            env.setFeedbackPresentationSuspended(false, by: "root.blockedApp")
            guard didStartSessionFromBlockedApp else { return }
            didStartSessionFromBlockedApp = false
            env.presentSessionStartedFeedback()
        }) {
            BlockedAppDetailView(
                onDismiss: env.dismissBlockedAppDetail,
                onSessionStarted: {
                    didStartSessionFromBlockedApp = true
                    env.dismissBlockedAppDetail()
                },
                onPushups: {
                    env.analytics.track(.pushupsEntryTapped.withProperties([
                        "source": .string("blocked_detail")
                    ]))
                    env.requestRoute(.pushups)
                    env.dismissBlockedAppDetail()
                }
            )
            .onAppear {
                env.setFeedbackPresentationSuspended(true, by: "root.blockedApp")
            }
        }
        .sheet(isPresented: Binding(
            get: { isAdaptiveIntroPending },
            set: { if !$0 { env.markAdaptiveIntroSeen() } }
        ), onDismiss: {
            env.setFeedbackPresentationSuspended(false, by: "root.adaptiveIntro")
        }) {
            AdaptiveExistingUserView()
                .interactiveDismissDisabled()
        }
        // Only one sheet can be presented from here, so someone owed both meets the adaptive
        // intro first and this one on the next launch.
        .sheet(isPresented: Binding(
            get: { isPushupsIntroPending },
            set: { if !$0 { env.markPushupsIntroSeen() } }
        ), onDismiss: {
            env.setFeedbackPresentationSuspended(false, by: "root.pushupsIntro")
        }) {
            PushupsIntroView(onStart: { env.requestRoute(.pushups) })
        }
    }

    /// Existing users from before the onboarding rewrite, who have not acknowledged it yet.
    private var isAdaptiveIntroPending: Bool {
        env.hasCompletedOnboarding
            && env.subscriptionManager.isPro
            && env.profile.onboardingCompletedAt == nil
            && !env.state.adaptiveIntroSeen
    }

    private var isPushupsIntroPending: Bool {
        env.hasCompletedOnboarding
            && env.subscriptionManager.isPro
            && !env.state.pushupsIntroSeen
            && !isAdaptiveIntroPending
    }

    private var streakCelebrationEligibilityToken: String {
        guard env.hasCompletedOnboarding,
              env.subscriptionManager.isPro,
              env.streakDays > 0,
              env.presentationFeedback == nil,
              !env.isPresentingBlockedAppDetail,
              !isAdaptiveIntroPending,
              !isPushupsIntroPending else { return "ineligible" }
        return "\(env.state.ledger.day.description)-\(env.streakDays)"
    }

    private var subscriptionLoading: some View {
        VStack(spacing: Theme.Space.m) {
            ProgressView().tint(Theme.cobalt)
            Text("Checking your subscription")
                .font(.sans(15, weight: .semibold))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paperBackground()
        .task { await env.subscriptionManager.refresh() }
    }

    @ViewBuilder
    private var mainContent: some View {
        ZStack {
            Group {
                switch selectedSection {
                case .home:
                    DashboardView(onNavigationDepthChange: { isShowingDetail = $0 })
                case .week:
                    WeekView(showsDoneButton: false)
                case .settings:
                    SettingsView(
                        showsDoneButton: false,
                        onNavigationDepthChange: { isShowingDetail = $0 }
                    )
                }
            }
            .id(selectedSection)
            .transition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isShowingDetail {
                FloatingBottomNavigation(
                    selection: Binding(get: { selectedSection }, set: selectSection)
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isShowingDetail)
        .onChange(of: selectedSection) { _, _ in isShowingDetail = false }
    }

    private func selectSection(_ section: AppSection) {
        guard section != selectedSection else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
            selectedSection = section
        }
    }

    private func applyPendingRoute(_ route: AppRoute?) {
        guard let route, env.hasCompletedOnboarding else { return }
        selectSection(.home)
        isShowingDetail = false
        // `.pushups` needs the Dashboard's navigation stack, so it consumes that one itself.
        guard route == .home else { return }
        env.consumePendingRoute()
    }

    private func presentStreakCelebrationIfNeeded() {
        guard streakCelebrationEligibilityToken != "ineligible" else { return }
        let day = env.state.ledger.day.description
        guard lastStreakCelebrationDay != day, celebratedStreakDays == 0 else { return }

        lastStreakCelebrationDay = day
        celebratedStreakDays = env.streakDays
        env.setFeedbackPresentationSuspended(true, by: "root.streakCelebration")
    }

    private func dismissStreakCelebration() {
        celebratedStreakDays = 0
        env.setFeedbackPresentationSuspended(false, by: "root.streakCelebration")
    }
}
