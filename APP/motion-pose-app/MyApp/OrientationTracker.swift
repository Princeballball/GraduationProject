import Combine
import CoreMotion
import Foundation

struct OrientationReading {
    // 角度：度；角速度：度／秒。
    let roll: Double
    let pitch: Double
    let yaw: Double
    let rotationX: Double
    let rotationY: Double
    let rotationZ: Double
}

@MainActor
final class OrientationTracker: ObservableObject {
    @Published private(set) var reading: OrientationReading?
    @Published private(set) var isRunning = false
    @Published private(set) var status = "準備讀取角度"

    private let motionManager = CMMotionManager()
    private let updateQueue = OperationQueue()
    private var sessionID = UUID()

    var isAvailable: Bool { motionManager.isDeviceMotionAvailable }

    init() {
        updateQueue.name = "Device motion updates"
        updateQueue.maxConcurrentOperationCount = 1
        if !isAvailable {
            status = "此裝置無法提供角度與角速度資料。"
        }
    }

    func start() {
        guard !isRunning, isAvailable else { return }
        guard CMMotionManager.availableAttitudeReferenceFrames().contains(.xArbitraryZVertical) else {
            status = "此裝置不支援需要的姿態參考座標。"
            return
        }

        sessionID = UUID()
        let currentSession = sessionID
        reading = nil
        isRunning = true
        status = "等待姿態資料…"
        motionManager.deviceMotionUpdateInterval = 0.05 // 每秒約 20 筆
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: updateQueue) { [weak self] data, error in
            let reading = data.map { motion in
                let degrees = 180.0 / Double.pi
                return OrientationReading(
                    roll: motion.attitude.roll * degrees,
                    pitch: motion.attitude.pitch * degrees,
                    yaw: motion.attitude.yaw * degrees,
                    rotationX: motion.rotationRate.x * degrees,
                    rotationY: motion.rotationRate.y * degrees,
                    rotationZ: motion.rotationRate.z * degrees
                )
            }
            let errorMessage = error?.localizedDescription

            Task { @MainActor [weak self] in
                guard let self, self.isRunning, self.sessionID == currentSession else { return }
                if let errorMessage {
                    self.stop()
                    self.status = "角度讀取失敗：\(errorMessage)"
                } else if let reading {
                    self.reading = reading
                    self.status = "正在讀取角度與角速度"
                }
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        motionManager.stopDeviceMotionUpdates()
        sessionID = UUID()
        isRunning = false
        status = "已暫停，保留最後一筆數值"
    }

    deinit {
        motionManager.stopDeviceMotionUpdates()
    }
}
