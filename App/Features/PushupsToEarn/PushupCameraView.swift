import AVFoundation
import SwiftUI
import UIKit

@MainActor
struct PushupCameraView: UIViewRepresentable {
    let detector: VisionPushupDetector
    let onSnapshot: @MainActor @Sendable (PushupDetectionSnapshot) -> Void
    let onError: @MainActor @Sendable (ExerciseDetectorError) -> Void

    init(
        detector: VisionPushupDetector = VisionPushupDetector(),
        onSnapshot: @escaping @MainActor @Sendable (PushupDetectionSnapshot) -> Void,
        onError: @escaping @MainActor @Sendable (ExerciseDetectorError) -> Void
    ) {
        self.detector = detector
        self.onSnapshot = onSnapshot
        self.onError = onError
    }

    func makeUIView(context: Context) -> PushupCameraPreviewView {
        let view = PushupCameraPreviewView()
        view.detector = detector
        view.previewLayer.session = detector.captureSession
        detector.start(onSnapshot: onSnapshot, onError: onError)
        return view
    }

    func updateUIView(_ view: PushupCameraPreviewView, context: Context) {
        detector.updateHandlers(onSnapshot: onSnapshot, onError: onError)
    }

    static func dismantleUIView(_ view: PushupCameraPreviewView, coordinator: Void) {
        view.previewLayer.session = nil
        view.detector?.stop()
        view.detector = nil
    }

}

final class PushupCameraPreviewView: UIView {
    var detector: VisionPushupDetector?

    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        previewLayer.videoGravity = .resizeAspectFill
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let angle = rotationAngle
        if let connection = previewLayer.connection {
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
        // The preview and the pose request must read the frame the same way up.
        detector?.setRotationAngle(angle)
    }

    /// Clockwise rotation that turns the sensor-native landscape frame upright for
    /// the orientation the interface is actually showing.
    private var rotationAngle: CGFloat {
        switch window?.windowScene?.interfaceOrientation {
        case .landscapeRight: 0
        case .portraitUpsideDown: 270
        case .landscapeLeft: 180
        default: VisionPushupDetector.portraitRotationAngle
        }
    }
}
