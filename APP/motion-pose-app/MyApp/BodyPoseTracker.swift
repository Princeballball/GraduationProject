@preconcurrency import AVFoundation
import Combine
import Vision

struct BodyJoint: Identifiable, Sendable {
    let name: String
    let x: Double
    let y: Double
    let confidence: Double

    var id: String { name }
    var displayName: String {
        name.replacingOccurrences(of: "VNHumanBodyPoseObservationJointName", with: "")
    }
}

@MainActor
final class BodyPoseTracker: NSObject, ObservableObject {
    @Published private(set) var joints: [BodyJoint] = []
    @Published private(set) var imageSize = CGSize.zero
    @Published private(set) var isRunning = false
    @Published private(set) var status = "準備相機"

    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let processor = BodyPoseProcessor()
    private let sessionQueue = DispatchQueue(label: "Body pose camera session")
    private let videoQueue = DispatchQueue(label: "Body pose video frames")
    private var isConfigured = false
    private var sessionID = UUID()
    private var desiredVideoOrientation: AVCaptureVideoOrientation = .portrait

    var isAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    override init() {
        super.init()
        if !isAvailable { status = "此裝置沒有可用的後置相機。" }
        processor.onPose = { [weak self] joints, size in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                self.imageSize = size
                self.joints = joints
                self.status = joints.isEmpty
                    ? "未偵測到人體，請讓全身進入畫面。"
                    : "偵測到 \(joints.count) 個關節點"
            }
        }
    }

    func start() {
        guard !isRunning, isAvailable else { return }
        isRunning = true
        sessionID = UUID()
        let currentSession = sessionID
        joints = []
        status = "正在取得相機權限…"

        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard isRunning, sessionID == currentSession else { return }
            guard granted else {
                isRunning = false
                status = "需要相機權限；請到 iPad「設定」允許此 App 使用相機。"
                return
            }

            do {
                if !isConfigured { try configureSession() }
                let captureSession = session
                sessionQueue.async { captureSession.startRunning() }
                status = "正在尋找身體關節…"
            } catch {
                isRunning = false
                status = "無法啟動相機：\(error.localizedDescription)"
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        sessionID = UUID()
        let captureSession = session
        // 模式切換前等相機確實停下，避免和 ARKit 同時爭用相機。
        sessionQueue.sync {
            if captureSession.isRunning { captureSession.stopRunning() }
        }
        status = "已暫停，保留最後一筆關節點"
    }

    func updateVideoOrientation(_ orientation: AVCaptureVideoOrientation) {
        desiredVideoOrientation = orientation
        guard let connection = output.connection(with: .video),
              connection.isVideoOrientationSupported,
              connection.videoOrientation != orientation else { return }
        connection.videoOrientation = orientation
        imageSize = .zero
        joints = []
    }

    private func configureSession() throws {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw PoseError.noCamera
        }
        let input = try AVCaptureDeviceInput(device: camera)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw PoseError.cannotConfigure
        }
        session.addInput(input)
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(processor, queue: videoQueue)
        session.addOutput(output)
        if let connection = output.connection(with: .video),
           connection.isVideoOrientationSupported {
            connection.videoOrientation = desiredVideoOrientation
        }
        isConfigured = true
    }
}

private enum PoseError: LocalizedError {
    case noCamera
    case cannotConfigure

    var errorDescription: String? {
        switch self {
        case .noCamera: "找不到後置相機。"
        case .cannotConfigure: "相機擷取設定失敗。"
        }
    }
}

private final class BodyPoseProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated(unsafe) var onPose: (([BodyJoint], CGSize) -> Void)?
    nonisolated(unsafe) private var lastFrameTime = -Double.infinity

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        guard time - lastFrameTime >= 0.1,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrameTime = time

        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        do {
            try handler.perform([request])
            let points = try request.results?.first?.recognizedPoints(.all) ?? [:]
            let joints = points.compactMap { name, point -> BodyJoint? in
                guard point.confidence >= 0.3 else { return nil }
                return BodyJoint(
                    name: name.rawValue.rawValue,
                    x: Double(point.location.x),
                    y: Double(point.location.y),
                    confidence: Double(point.confidence)
                )
            }.sorted { $0.name < $1.name }
            let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
            onPose?(joints, size)
        } catch {
            onPose?([], .zero)
        }
    }
}
