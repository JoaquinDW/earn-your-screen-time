import SwiftUI

struct StudyToEarnView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var model = StudyToEarnModel()
    let onUseMinutes: () -> Void

    var body: some View {
        Group {
            if model.phase == .camera {
                camera
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        content
                    }
                    .padding(.horizontal, Theme.Space.gutter)
                    .padding(.top, Theme.Space.l)
                    .padding(.bottom, Theme.Space.xxl)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .background(Night.ground.ignoresSafeArea())
        .foregroundStyle(Night.text)
        .navigationTitle(Text("study.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Night.ground, for: .navigationBar)
        .trackScreen("study_to_earn", analytics: env.analytics)
        .onAppear { model.appeared(in: env) }
        .onDisappear { model.close(in: env) }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .introduction:
            introduction
        case .preparing:
            processing(title: "study.preparing.title", detail: "study.preparing.detail")
        case .processing:
            processing(title: "study.processing.title", detail: "study.processing.detail")
        case .checking:
            processing(title: "study.checking.title", detail: "study.checking.detail")
        case .question:
            question
        case .retry:
            retry
        case .success:
            success
        case .dailyCap:
            dailyCap
        case .error:
            error
        case .camera:
            EmptyView()
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            NightEyebrow(text: "study.mission")
            Text("study.intro.title")
                .font(.serif(42))
                .fixedSize(horizontal: false, vertical: true)
            Text("study.intro.detail \(model.rewardMinutes)")
                .font(.sans(17))
                .foregroundStyle(Night.textSoft)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Space.m) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Night.cobaltText)
                    .frame(width: 56, height: 56)
                    .background(Night.cobaltWash, in: .rect(cornerRadius: Night.cardRadius))
                    .accessibilityHidden(true)
                Text("study.intro.examples")
                    .font(.sans(14, weight: .medium))
                    .foregroundStyle(Night.textMuted)
            }
            .padding(Theme.Space.m)
            .background(Night.panel, in: .rect(cornerRadius: Night.panelRadius))

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Label("study.privacy.title", systemImage: "hand.raised")
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(Night.textSoft)
                Text("study.privacy.detail")
                    .font(.sans(13))
                    .foregroundStyle(Night.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("study.scan.cta") { Task { await model.begin(in: env) } }
                .buttonStyle(.nightPill)
        }
    }

    private var camera: some View {
        ZStack {
            StudyCameraView(
                captureRequest: model.captureRequest,
                onCapture: { model.received($0, in: env) },
                onError: model.cameraFailed
            )
            .ignoresSafeArea()

            VStack(spacing: Theme.Space.l) {
                VStack(spacing: Theme.Space.s) {
                    Text("study.camera.title").font(.sans(18, weight: .semibold))
                    Text("study.camera.detail")
                        .font(.sans(13))
                        .foregroundStyle(Night.textSoft)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, Theme.Space.l)
                .padding(.vertical, Theme.Space.m)
                .background(Night.ground.opacity(0.86), in: .rect(cornerRadius: Night.panelRadius))

                RoundedRectangle(cornerRadius: Night.panelRadius)
                    .stroke(Night.text.opacity(0.72), lineWidth: 2)
                    .overlay(alignment: .topLeading) {
                        Text("study.camera.guide")
                            .font(.sans(11, weight: .semibold))
                            .padding(Theme.Space.s)
                            .foregroundStyle(Night.textSoft)
                    }
                    .padding(.horizontal, Theme.Space.l)

                Button { model.takePhoto() } label: {
                    Label("study.camera.cta", systemImage: "camera.fill")
                }
                .buttonStyle(.nightPill(prominent: false))
                .padding(.bottom, Theme.Space.l)
            }
            .padding(.top, Theme.Space.l)
        }
    }

    private var question: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            NightEyebrow(text: "study.question.eyebrow")
            Text("study.question.title")
                .font(.serif(40))
            Text(model.question?.text ?? "")
                .font(.sans(20, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, Theme.Space.s)

            TextEditor(text: $model.answer)
                .font(.sans(16))
                .scrollContentBackground(.hidden)
                .padding(Theme.Space.m)
                .frame(minHeight: 176)
                .background(Night.panel, in: .rect(cornerRadius: Night.panelRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: Night.panelRadius)
                        .stroke(Night.edge, lineWidth: 1)
                }
                .accessibilityLabel(Text("study.answer.placeholder"))

            Button("study.answer.cta") { Task { await model.submit(in: env) } }
                .buttonStyle(.nightPill)
                .disabled(!model.canSubmit)

            Button("study.question.different") { Task { await model.regenerate(in: env) } }
                .buttonStyle(.quietLink)
                .frame(maxWidth: .infinity)
                .disabled(!model.canRegenerate)
        }
    }

    private var retry: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            stateSymbol("arrow.trianglehead.counterclockwise", color: Night.cobaltText)
            NightEyebrow(text: "study.retry.eyebrow")
            Text("study.retry.title").font(.serif(42))
            Text(model.feedback)
                .font(.sans(17))
                .foregroundStyle(Night.textSoft)
                .fixedSize(horizontal: false, vertical: true)
            Button("study.retry.cta") { model.tryAnswerAgain() }
                .buttonStyle(.nightPill)
            Button("study.scan.another") { Task { await model.scanAnotherPage(in: env) } }
                .buttonStyle(.quietLink)
                .frame(maxWidth: .infinity)
        }
    }

    private var success: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            stateSymbol("checkmark", color: Night.moss)
            NightEyebrow(text: "study.success.eyebrow")
            Text("study.success.title \(model.rewardSeconds / 60)")
                .font(.serif(44))
                .fixedSize(horizontal: false, vertical: true)
            Text("study.success.detail")
                .font(.sans(17))
                .foregroundStyle(Night.textSoft)
            Button("study.success.use") {
                dismiss()
                onUseMinutes()
            }
            .buttonStyle(.nightPill)
            Button("study.success.again") { model.studyAgain() }
                .buttonStyle(.quietLink)
                .frame(maxWidth: .infinity)
        }
    }

    private var dailyCap: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            stateSymbol("moon.stars", color: Night.textMuted)
            NightEyebrow(text: "study.limit.eyebrow")
            Text("study.limit.title").font(.serif(42))
            if let date = model.configuration?.nextAvailableAt {
                Text("study.limit.detail \(date.formatted(date: .omitted, time: .shortened))")
                    .font(.sans(17))
                    .foregroundStyle(Night.textSoft)
            } else {
                Text("study.limit.detail.fallback")
                    .font(.sans(17))
                    .foregroundStyle(Night.textSoft)
            }
        }
    }

    private var error: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            stateSymbol("viewfinder", color: Night.textMuted)
            NightEyebrow(text: "study.error.eyebrow")
            Text("study.error.title").font(.serif(42))
            Text(model.errorMessage)
                .font(.sans(16))
                .foregroundStyle(Night.textSoft)
                .fixedSize(horizontal: false, vertical: true)
            Button("study.error.retry") { Task { await model.retryFailedOperation(in: env) } }
                .buttonStyle(.nightPill)
            if model.failedOperation != .access {
                Button("study.scan.another") { Task { await model.scanAnotherPage(in: env) } }
                    .buttonStyle(.quietLink)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func processing(title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            ProgressView().tint(Night.cobalt).controlSize(.large)
            Text(title).font(.serif(38))
            Text(detail).font(.sans(16)).foregroundStyle(Night.textSoft)
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                ForEach([0.92, 0.74, 0.86], id: \.self) { width in
                    Capsule()
                        .fill(Night.text.opacity(0.09))
                        .frame(maxWidth: .infinity)
                        .frame(height: 12)
                        .scaleEffect(x: width, anchor: .leading)
                }
            }
            .padding(Theme.Space.l)
            .background(Night.panel, in: .rect(cornerRadius: Night.panelRadius))
        }
        .accessibilityElement(children: .combine)
    }

    private func stateSymbol(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 64, height: 64)
            .background(Night.panel, in: .rect(cornerRadius: Night.panelRadius))
            .accessibilityHidden(true)
    }
}
