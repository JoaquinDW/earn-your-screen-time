import Foundation
import ImageIO
import UIKit
import Vision

struct StudyOCRResult: Equatable, Sendable {
    let text: String
    let confidence: Float
}

protocol StudyOCRServing: Sendable {
    func recognizeText(in image: UIImage, locale: Locale) async throws -> StudyOCRResult
}

enum StudyOCRError: LocalizedError {
    case unreadable
    case tooLittleText

    var errorDescription: String? {
        switch self {
        case .unreadable: "We could not read this scan. Try again with steadier light and focus."
        case .tooLittleText: "Try scanning a fuller page or clearer notes."
        }
    }
}

struct VisionStudyOCRService: StudyOCRServing {
    func recognizeText(in image: UIImage, locale: Locale) async throws -> StudyOCRResult {
        guard let cgImage = image.cgImage else { throw StudyOCRError.unreadable }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = [locale.identifier]
                do {
                    try VNImageRequestHandler(cgImage: cgImage, orientation: orientation).perform([request])
                    let candidates = (request.results ?? []).compactMap { $0.topCandidates(1).first }
                    let text = candidates.map(\.string).joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { throw StudyOCRError.unreadable }
                    guard text.count >= 80 else { throw StudyOCRError.tooLittleText }
                    let confidence = candidates.isEmpty
                        ? 0
                        : candidates.reduce(Float.zero) { $0 + $1.confidence } / Float(candidates.count)
                    guard confidence >= 0.35 else { throw StudyOCRError.unreadable }
                    continuation.resume(returning: StudyOCRResult(text: text, confidence: confidence))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
