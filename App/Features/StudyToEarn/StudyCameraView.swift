import AVFoundation
import SwiftUI
import UIKit

struct StudyCameraView: UIViewControllerRepresentable {
    let captureRequest: Int
    let onCapture: (UIImage) -> Void
    let onError: (Error) -> Void

    func makeUIViewController(context: Context) -> StudyCameraViewController {
        StudyCameraViewController(onCapture: onCapture, onError: onError)
    }

    func updateUIViewController(_ controller: StudyCameraViewController, context: Context) {
        controller.capture(request: captureRequest)
    }

    static func dismantleUIViewController(_ controller: StudyCameraViewController, coordinator: Void) {
        controller.stop()
    }
}

private final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

final class StudyCameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.earnit.study-camera")
    private let onCapture: (UIImage) -> Void
    private let onError: (Error) -> Void
    private var lastCaptureRequest = 0
    private var pendingCaptureRequest: Int?
    private var configured = false

    init(onCapture: @escaping (UIImage) -> Void, onError: @escaping (Error) -> Void) {
        self.onCapture = onCapture
        self.onError = onError
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = CameraPreviewView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let preview = view as? CameraPreviewView else { return }
        preview.previewLayer.session = session
        preview.previewLayer.videoGravity = .resizeAspectFill
        configure()
    }

    func capture(request: Int) {
        sessionQueue.async { [weak self] in
            guard let self, request > 0, request != lastCaptureRequest else { return }
            guard configured, session.isRunning else {
                pendingCaptureRequest = request
                return
            }
            captureOnSessionQueue(request: request)
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self = self, session.isRunning else { return }
            session.stopRunning()
        }
    }

    private func configure() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                session.beginConfiguration()
                do {
                    session.sessionPreset = .photo
                    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                        throw CameraError.unavailable
                    }
                    let input = try AVCaptureDeviceInput(device: device)
                    guard session.canAddInput(input), session.canAddOutput(output) else {
                        throw CameraError.configurationFailed
                    }
                    session.addInput(input)
                    session.addOutput(output)
                } catch {
                    session.commitConfiguration()
                    throw error
                }
                session.commitConfiguration()
                configured = true
                session.startRunning()
                if let pendingCaptureRequest {
                    captureOnSessionQueue(request: pendingCaptureRequest)
                    self.pendingCaptureRequest = nil
                }
            } catch {
                Task { @MainActor in self.onError(error) }
            }
        }
    }

    private func captureOnSessionQueue(request: Int) {
        guard request != lastCaptureRequest else { return }
        lastCaptureRequest = request
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            Task { @MainActor in onError(error) }
            return
        }
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            Task { @MainActor in onError(CameraError.invalidPhoto) }
            return
        }
        Task { @MainActor in onCapture(image) }
    }
}

enum CameraError: LocalizedError {
    case unavailable
    case configurationFailed
    case invalidPhoto
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .unavailable: "The camera is not available on this device."
        case .configurationFailed: "Earnit could not start the camera."
        case .invalidPhoto: "Earnit could not process that photo."
        case .permissionDenied: "Allow camera access in Settings to scan study material."
        }
    }
}
