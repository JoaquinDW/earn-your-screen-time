import SwiftUI

/// Onboarding until it is done, then the app's three top-level sections.
struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedSection: AppSection = .home
    @State private var sectionTransitionEdge: Edge = .trailing
    @State private var isShowingDetail = false

    var body: some View {
        Group {
            if !env.hasCompletedOnboarding {
                OnboardingView()
            } else if env.subscriptionManager.status == .unknown {
                subscriptionLoading
            } else if env.requiresSubscription {
                ProPaywallView(allowsDismiss: false)
            } else {
                mainContent
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: env.hasCompletedOnboarding)
        .onAppear { applyPendingRoute(env.pendingRoute) }
        .onChange(of: env.pendingRoute) { _, route in
            applyPendingRoute(route)
        }
        .fullScreenCover(isPresented: Binding(
            get: { env.hasCompletedOnboarding && env.isPresentingBlockedAppDetail },
            set: { if !$0 { env.dismissBlockedAppDetail() } }
        )) {
            BlockedAppDetailView(onDismiss: env.dismissBlockedAppDetail)
        }
        .sheet(isPresented: Binding(
            get: {
                env.hasCompletedOnboarding
                    && env.subscriptionManager.isPro
                    && env.profile.onboardingCompletedAt == nil
                    && !env.state.adaptiveIntroSeen
            },
            set: { if !$0 { env.markAdaptiveIntroSeen() } }
        )) {
            AdaptiveExistingUserView()
                .interactiveDismissDisabled()
        }
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
                    DashboardView(onNavigate: selectSection)
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
            .transition(sectionTransition)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isShowingDetail {
                FloatingBottomNavigation(selection: Binding(
                    get: { selectedSection },
                    set: selectSection
                ))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isShowingDetail)
        .onChange(of: selectedSection) { _, _ in isShowingDetail = false }
    }

    private var sectionTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: sectionTransitionEdge),
            removal: .opacity.animation(.easeOut(duration: 0.16))
        )
    }

    private func selectSection(_ section: AppSection) {
        guard section != selectedSection else { return }
        sectionTransitionEdge = section.index > selectedSection.index ? .trailing : .leading
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.36)) {
            selectedSection = section
        }
    }

    private func applyPendingRoute(_ route: AppRoute?) {
        guard route == .home, env.hasCompletedOnboarding else { return }
        selectSection(.home)
        isShowingDetail = false
        env.consumePendingRoute()
    }
}
