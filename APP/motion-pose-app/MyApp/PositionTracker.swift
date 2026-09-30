import ARKit
import Combine
import Foundation

struct PositionReading {
    let x: Double
    let y: Double
    let z: Double
}

@MainActor
final class PositionTracker: NSObject, ObservableObject, ARSessionDelegate {
    @Published private(set) var reading: PositionReading?
    @Published private(set) var isRunning = false
    @Published private(set) var status = "準備定位"

    let session = ARSession()
    private var origin: SIMD3<Float>?
    private var latestPosition: SIMD3<Float>?
    private var lastUpdateTime: TimeInterval = 0

    var isAvailable: Bool { ARWorldTrackingConfiguration.isSupported }

    override init() {
        super.init()
        session.delegate = self
        session.delegateQueue = .main
        if !isAvailable {
            status = "此裝置不支援 ARKit 空間定位，請使用支援的實體 iPhone。"
        }
    }

    func start() {
        guard !isRunning, isAvailable else { return }
        origin = nil
        latestPosition = nil
        lastUpdateTime = 0
        reading = nil
        isRunning = true
        status = "正在尋找定位特徵，請緩慢移動手機…"

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        guard isRunning else { return }
        session.pause()
        isRunning = false
        status = "已暫停，保留最後一筆位移"
    }

    func resetOrigin() {
        guard let latestPosition, isRunning else { return }
        origin = latestPosition
        reading = PositionReading(x: 0, y: 0, z: 0)
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isRunning else { return }

        guard case .normal = frame.camera.trackingState else {
            status = "定位品質不足，請將鏡頭對準有紋理且光線充足的環境。"
            return
        }

        let translation = frame.camera.transform.columns.3
        let position = SIMD3<Float>(translation.x, translation.y, translation.z)
        latestPosition = position
        if origin == nil { origin = position }

        guard frame.timestamp - lastUpdateTime >= 1.0 / 20.0,
              let origin else { return }
        lastUpdateTime = frame.timestamp

        let displacement = position - origin
        reading = PositionReading(
            x: Double(displacement.x),
            y: Double(displacement.y),
            z: Double(displacement.z)
        )
        status = "正在追蹤位置"
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        guard isRunning else { return }
        stop()
        if let arError = error as? ARError, arError.code == .cameraUnauthorized {
            status = "需要相機權限；請到 iPhone「設定」允許此 App 使用相機。"
        } else {
            status = "定位失敗：\(error.localizedDescription)"
        }
    }
}
