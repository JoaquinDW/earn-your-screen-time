import AVFoundation
import EarnDomain
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class StudyToEarnModel {
    enum Phase: Equatable {
        case introduction
        case preparing
        case camera
        case processing
        case question
        case checking
        case retry
        case success
        case dailyCap
        case error
    }

    enum FailedOperation: Equatable {
        case access
        case scan
        case question
        case answer
    }

    private(set) var phase = Phase.introduction
    private(set) var configuration: StudyConfiguration?
    private(set) var question: StudyQuestion?
    private(set) var feedback = ""
    private(set) var errorMessage = ""
    private(set) var failedOperation = FailedOperation.access
    private(set) var captureRequest = 0
    private(set) var rewardSeconds = 0
    var answer = ""

    private var sourceText: String?
    private var requestID = UUID()
    private var opened = false
    private var started = false
    private var completed = false
    private var processingTask: Task<Void, Never>?

    var rewardMinutes: Int { (configuration?.rewardSeconds ?? 900) / 60 }
    var canRegenerate: Bool {
        guard let configuration, let question else { return false }
        return question.regenerationCount < configuration.maxRegenerations
    }
    var canSubmit: Bool { !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func appeared(in environment: AppEnvironment) {
        guard !opened else { return }
        opened = true
        environment.analytics.track(.studyToEarnOpened)
    }

    func begin(in environment: AppEnvironment) async {
        phase = .preparing
        do {
            let config = try await environment.prepareStudyConfiguration()
            configuration = config
            guard config.canEarnFullReward else {
                phase = .dailyCap
                environment.analytics.track(.studyDailyCapReached)
                return
            }
            guard environment.canFitStudyReward(seconds: config.rewardSeconds) else {
                throw StudyAccessError.walletCapacity
            }
            try await requestCameraAccess()
            started = true
            environment.analytics.track(.studyScanStarted)
            phase = .camera
        } catch {
            show(error, operation: .access)
        }
    }

    func takePhoto() {
        captureRequest += 1
    }

    func received(_ image: UIImage, in environment: AppEnvironment) {
        environment.analytics.track(.studyScanCaptured)
        phase = .processing
        processingTask?.cancel()
        processingTask = Task { [weak self] in
            guard let self else { return }
            let result: StudyOCRResult
            do {
                result = try await environment.studyOCR.recognizeText(
                    in: image,
                    locale: environment.appLanguage.locale
                )
                try Task.checkCancellation()
                sourceText = result.text
                environment.analytics.track(.studyOCRSucceeded.withProperties([
                    "character_count_bucket": .string(Self.characterBucket(result.text.count)),
                    "confidence_bucket": .string(Self.confidenceBucket(Double(result.confidence)))
                ]))
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                environment.analytics.track(.studyOCRFailed.withProperties([
                    "reason": .string(Self.safeErrorCode(error))
                ]))
                show(error, operation: .scan)
                return
            }
            do {
                try await generateQuestion(in: environment)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                show(error, operation: .question)
            }
        }
    }

    func cameraFailed(_ error: Error) {
        show(error, operation: .scan)
    }

    func retryFailedOperation(in environment: AppEnvironment) async {
        switch failedOperation {
        case .access:
            await begin(in: environment)
        case .scan:
            phase = .camera
        case .question:
            phase = .processing
            do {
                try await generateQuestion(in: environment)
            } catch {
                show(error, operation: .question)
            }
        case .answer:
            await submit(in: environment)
        }
    }

    func regenerate(in environment: AppEnvironment) async {
        guard canRegenerate, let sessionID = question?.sessionID else { return }
        phase = .processing
        do {
            question = try await environment.study.regenerate(sessionID: sessionID)
            answer = ""
            feedback = ""
            environment.analytics.track(.studyQuestionRegenerated)
            phase = .question
        } catch {
            show(error, operation: .question)
        }
    }

    func submit(in environment: AppEnvironment) async {
        guard let question, canSubmit else { return }
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard environment.canFitStudyReward(seconds: configuration?.rewardSeconds ?? 900) else {
            show(StudyAccessError.walletCapacity, operation: .answer)
            return
        }
        phase = .checking
        environment.analytics.track(.studyAnswerSubmitted.withProperties([
            "attempt": .int(question.answerAttemptCount + 1)
        ]))
        do {
            let evaluation = try await environment.study.submit(answer: trimmed, sessionID: question.sessionID)
            feedback = evaluation.feedback
            if evaluation.pass {
                guard let reward = evaluation.reward else { throw StudyAccessError.invalidReward }
                _ = try environment.applyStudyReward(reward)
                rewardSeconds = reward.amountSeconds
                sourceText = nil
                answer = ""
                completed = true
                environment.analytics.track(.studyAnswerPassed.withProperties([
                    "attempt": .int(question.answerAttemptCount + 1),
                    "confidence_bucket": .string(Self.confidenceBucket(evaluation.confidence))
                ]))
                phase = .success
            } else {
                feedback = evaluation.feedback
                self.question = StudyQuestion(
                    sessionID: question.sessionID,
                    text: question.text,
                    regenerationCount: question.regenerationCount,
                    answerAttemptCount: question.answerAttemptCount + 1
                )
                environment.analytics.track(.studyAnswerFailed.withProperties([
                    "attempt": .int(question.answerAttemptCount + 1),
                    "confidence_bucket": .string(Self.confidenceBucket(evaluation.confidence))
                ]))
                phase = .retry
            }
        } catch {
            if (error as? StudyServiceError)?.code == "daily_cap_reached" {
                environment.analytics.track(.studyDailyCapReached)
                phase = .dailyCap
            } else {
                show(error, operation: .answer)
            }
        }
    }

    func tryAnswerAgain() {
        answer = ""
        phase = .question
    }

    func scanAnotherPage(in environment: AppEnvironment) async {
        if let sessionID = question?.sessionID {
            await environment.study.abandon(sessionID: sessionID)
        }
        resetTransient()
        do {
            try await requestCameraAccess()
            environment.analytics.track(.studyScanStarted)
            phase = .camera
        } catch {
            show(error, operation: .access)
        }
    }

    func studyAgain() {
        resetTransient()
        started = false
        completed = false
        phase = .introduction
    }

    func close(in environment: AppEnvironment) {
        let sessionID = question?.sessionID
        let shouldAbandon = started && !completed
        processingTask?.cancel()
        processingTask = nil
        resetTransient()
        if shouldAbandon {
            environment.analytics.track(.studyFlowAbandoned)
            if let sessionID {
                Task { await environment.study.abandon(sessionID: sessionID) }
            }
        }
    }

    private func generateQuestion(in environment: AppEnvironment) async throws {
        guard let sourceText else { throw StudyOCRError.unreadable }
        question = try await environment.study.start(
            sourceText: sourceText,
            locale: environment.appLanguage.locale.identifier,
            requestID: requestID
        )
        answer = ""
        environment.analytics.track(.studyQuestionGenerated)
        phase = .question
    }

    private func requestCameraAccess() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                throw CameraError.permissionDenied
            }
        case .denied, .restricted:
            throw CameraError.permissionDenied
        @unknown default:
            throw CameraError.unavailable
        }
    }

    private func show(_ error: Error, operation: FailedOperation) {
        failedOperation = operation
        errorMessage = error.localizedDescription
        phase = .error
    }

    private func resetTransient() {
        sourceText = nil
        question = nil
        answer = ""
        feedback = ""
        errorMessage = ""
        requestID = UUID()
    }

    private static func characterBucket(_ count: Int) -> String {
        switch count {
        case ..<250: "under_250"
        case ..<1_000: "250_to_999"
        default: "1000_plus"
        }
    }

    private static func confidenceBucket(_ confidence: Double) -> String {
        switch confidence {
        case ..<0.5: "low"
        case ..<0.8: "medium"
        default: "high"
        }
    }

    private static func safeErrorCode(_ error: Error) -> String {
        if let serviceError = error as? StudyServiceError, let code = serviceError.code { return code }
        if error is StudyOCRError { return "ocr_quality" }
        if error is CameraError { return "camera" }
        return "unknown"
    }
}
