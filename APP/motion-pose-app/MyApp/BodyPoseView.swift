import AVFoundation
import SwiftUI
import Vision

struct BodyPoseView: View {
    @ObservedObject var telemetry: TelemetryClient
    @StateObject private var tracker = BodyPoseTracker()
    @Environment(\.scenePhase) private var scenePhase
    @State private var shouldTrack = true

    var body: some View {
        GeometryReader { viewport in
            let landscape = viewport.size.width > viewport.size.height
            let previewWidth = min(max(viewport.size.width - 32, 1), landscape ? 640 : 400)
            let previewHeight = previewWidth * (landscape ? 9.0 / 16.0 : 16.0 / 9.0)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                Text("身體關節偵測")
                    .font(.largeTitle.bold())

                Text(tracker.status)
                    .foregroundStyle(.secondary)

                ZStack {
                    BodyCameraPreview(
                        session: tracker.session,
                        onOrientation: tracker.updateVideoOrientation
                    )
                    JointOverlay(joints: tracker.joints, imageSize: tracker.imageSize)
                        .allowsHitTesting(false)
                }
                .frame(width: previewWidth, height: previewHeight)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: .infinity)

                Button(tracker.isRunning ? "暫停關節偵測" : "開始關節偵測") {
                    shouldTrack = !tracker.isRunning
                    updateTracking()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!tracker.isAvailable)

                Text("使用 iPad 後置相機辨識畫面中最主要的人體，直向或橫向都可以。下方是影像中的 2D 座標，X、Y 範圍為 0～1，並附有每個點的信心值。請讓全身盡量進入畫面。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(tracker.joints) { joint in
                    HStack {
                        Text(joint.displayName)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(String(format: "x %.3f  y %.3f  %.0f%%", joint.x, joint.y, joint.confidence * 100))
                            .font(.system(.caption, design: .monospaced))
                    }
                    .padding(.vertical, 4)
                }
                }
                .padding()
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { updateTracking() }
        .onChange(of: scenePhase) { _, _ in updateTracking() }
        .onReceive(tracker.$joints) { joints in
            if tracker.isRunning { telemetry.sendBodyPose(joints: joints, imageSize: tracker.imageSize) }
        }
        .onDisappear { tracker.stop() }
    }

    private func updateTracking() {
        if scenePhase == .active && shouldTrack {
            tracker.start()
        } else {
            tracker.stop()
        }
    }
}

private struct BodyCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let onOrientation: (AVCaptureVideoOrientation) -> Void

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onOrientation = onOrientation
        return view
    }

    func updateUIView(_ view: PreviewUIView, context: Context) {
        view.onOrientation = onOrientation
        view.updateRotation()
    }
}

private final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var onOrientation: ((AVCaptureVideoOrientation) -> Void)?
    private var lastReportedOrientation: AVCaptureVideoOrientation?

    override func layoutSubviews() {
        super.layoutSubviews()
        updateRotation()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateRotation()
    }

    func updateRotation() {
        guard let orientation = window?.windowScene?.effectiveGeometry.interfaceOrientation,
              let connection = previewLayer.connection else { return }

        let videoOrientation: AVCaptureVideoOrientation
        switch orientation {
        case .portrait:
            videoOrientation = .portrait
        case .portraitUpsideDown:
            videoOrientation = .portraitUpsideDown
        case .landscapeLeft:
            videoOrientation = .landscapeLeft
        case .landscapeRight:
            videoOrientation = .landscapeRight
        default:
            return
        }
        if connection.isVideoOrientationSupported,
           connection.videoOrientation != videoOrientation {
            connection.videoOrientation = videoOrientation
        }
        if lastReportedOrientation != videoOrientation {
            lastReportedOrientation = videoOrientation
            Task { @MainActor [weak self] in
                self?.onOrientation?(videoOrientation)
            }
        }
    }
}

private struct JointOverlay: View {
    let joints: [BodyJoint]
    let imageSize: CGSize

    private let links: [(String, String)] = [
        (.neck, .leftShoulder), (.neck, .rightShoulder),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .rightHip), (.leftHip, .leftKnee),
        (.leftKnee, .leftAnkle), (.rightHip, .rightKnee),
        (.rightKnee, .rightAnkle)
    ]

    var body: some View {
        Canvas { context, size in
            guard imageSize.width > 0, imageSize.height > 0 else { return }
            let scale = max(size.width / imageSize.width, size.height / imageSize.height)
            let width = imageSize.width * scale
            let height = imageSize.height * scale
            let offsetX = (size.width - width) / 2
            let offsetY = (size.height - height) / 2

            func location(_ joint: BodyJoint) -> CGPoint {
                CGPoint(x: offsetX + joint.x * width, y: offsetY + (1 - joint.y) * height)
            }

            let points = Dictionary(uniqueKeysWithValues: joints.map { ($0.name, $0) })
            for (first, second) in links {
                guard let a = points[first], let b = points[second] else { continue }
                var path = Path()
                path.move(to: location(a))
                path.addLine(to: location(b))
                context.stroke(path, with: .color(.yellow), lineWidth: 3)
            }
            for joint in joints {
                let point = location(joint)
                let marker = Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
                context.fill(marker, with: .color(.green))
            }
        }
    }
}

private extension String {
    static let neck = VNHumanBodyPoseObservation.JointName.neck.rawValue.rawValue
    static let leftShoulder = VNHumanBodyPoseObservation.JointName.leftShoulder.rawValue.rawValue
    static let rightShoulder = VNHumanBodyPoseObservation.JointName.rightShoulder.rawValue.rawValue
    static let leftElbow = VNHumanBodyPoseObservation.JointName.leftElbow.rawValue.rawValue
    static let rightElbow = VNHumanBodyPoseObservation.JointName.rightElbow.rawValue.rawValue
    static let leftWrist = VNHumanBodyPoseObservation.JointName.leftWrist.rawValue.rawValue
    static let rightWrist = VNHumanBodyPoseObservation.JointName.rightWrist.rawValue.rawValue
    static let leftHip = VNHumanBodyPoseObservation.JointName.leftHip.rawValue.rawValue
    static let rightHip = VNHumanBodyPoseObservation.JointName.rightHip.rawValue.rawValue
    static let leftKnee = VNHumanBodyPoseObservation.JointName.leftKnee.rawValue.rawValue
    static let rightKnee = VNHumanBodyPoseObservation.JointName.rightKnee.rawValue.rawValue
    static let leftAnkle = VNHumanBodyPoseObservation.JointName.leftAnkle.rawValue.rawValue
    static let rightAnkle = VNHumanBodyPoseObservation.JointName.rightAnkle.rawValue.rawValue
}
