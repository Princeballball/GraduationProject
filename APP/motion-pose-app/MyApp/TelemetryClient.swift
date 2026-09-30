import Combine
import Foundation
import UIKit

@MainActor
final class TelemetryClient: ObservableObject {
    @Published var endpoint: String {
        didSet { UserDefaults.standard.set(endpoint, forKey: "djangoTelemetryEndpoint") }
    }
    @Published var isEnabled = false {
        didSet {
            status = isEnabled ? "傳送已開啟，等待數值。" : "已停止傳送資料。"
        }
    }
    @Published private(set) var status = "未傳送資料；填入 API 網址後可手動開啟。"

    private var lastSentAt: [String: Date] = [:]
    private var inFlight = Set<String>()
    private let deviceID: String
    private let deviceKind: String

    init() {
        endpoint = UserDefaults.standard.string(forKey: "djangoTelemetryEndpoint") ?? ""
        if let savedID = UserDefaults.standard.string(forKey: "telemetryDeviceID") {
            deviceID = savedID
        } else {
            let newID = UUID().uuidString
            UserDefaults.standard.set(newID, forKey: "telemetryDeviceID")
            deviceID = newID
        }
        deviceKind = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
    }

    func sendMotion(position: PositionReading?, orientation: OrientationReading?) {
        guard position != nil || orientation != nil else { return }
        let payload = MotionPayload(
            positionM: position.map { Vector3(x: $0.x, y: $0.y, z: $0.z) },
            attitudeDeg: orientation.map { Attitude(roll: $0.roll, pitch: $0.pitch, yaw: $0.yaw) },
            angularVelocityDegS: orientation.map {
                Vector3(x: $0.rotationX, y: $0.rotationY, z: $0.rotationZ)
            }
        )
        send(TelemetryEvent(deviceID: deviceID, deviceKind: deviceKind, type: "motion", motion: payload, bodyPose: nil))
    }

    func sendBodyPose(joints: [BodyJoint], imageSize: CGSize) {
        let points = Dictionary(uniqueKeysWithValues: joints.map {
            ($0.name, JointPayload(x: $0.x, y: $0.y, confidence: $0.confidence))
        })
        send(TelemetryEvent(
            deviceID: deviceID,
            deviceKind: deviceKind,
            type: "body_pose",
            motion: nil,
            bodyPose: BodyPosePayload(
                coordinateSystem: "normalized_image_bottom_left",
                imageSizePx: imageSize.width > 0 && imageSize.height > 0
                    ? ImageSize(width: Int(imageSize.width), height: Int(imageSize.height))
                    : nil,
                joints: points
            )
        ))
    }

    private func send(_ event: TelemetryEvent) {
        guard isEnabled else { return }
        let address = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: address),
              let host = url.host,
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || (scheme == "http" && Self.isPrivateIPv4(host)) else {
            status = "請輸入 HTTPS 網址，或熱點內 Mac 的私人 IP HTTP 網址。"
            return
        }

        let now = Date()
        guard !inFlight.contains(event.type),
              now.timeIntervalSince(lastSentAt[event.type] ?? .distantPast) >= 0.2 else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(event)
        } catch {
            status = "資料編碼失敗：\(error.localizedDescription)"
            return
        }

        lastSentAt[event.type] = now
        inFlight.insert(event.type)
        Task {
            defer { inFlight.remove(event.type) }
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let response = response as? HTTPURLResponse,
                      (200...299).contains(response.statusCode) else {
                    status = "API 回應失敗，請確認網址與伺服器。"
                    return
                }
                status = event.type == "motion" ? "三軸資料已傳送" : "關節資料已傳送"
            } catch {
                status = "傳送失敗：\(error.localizedDescription)"
            }
        }
    }

    private static func isPrivateIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        let octets = parts.compactMap { UInt8($0) }
        guard parts.count == 4, octets.count == 4 else { return false }

        return octets[0] == 10
            || (octets[0] == 172 && (16...31).contains(octets[1]))
            || (octets[0] == 192 && octets[1] == 168)
    }
}

private struct TelemetryEvent: Encodable {
    let schemaVersion = 1
    let deviceID: String
    let deviceKind: String
    let type: String
    let timestampMs = Int64(Date().timeIntervalSince1970 * 1_000)
    let motion: MotionPayload?
    let bodyPose: BodyPosePayload?
}

private struct MotionPayload: Encodable {
    let positionM: Vector3?
    let attitudeDeg: Attitude?
    let angularVelocityDegS: Vector3?
}

private struct BodyPosePayload: Encodable {
    let coordinateSystem: String
    let imageSizePx: ImageSize?
    let joints: [String: JointPayload]
}

private struct ImageSize: Encodable {
    let width: Int
    let height: Int
}

private struct Vector3: Encodable {
    let x: Double
    let y: Double
    let z: Double
}

private struct Attitude: Encodable {
    let roll: Double
    let pitch: Double
    let yaw: Double
}

private struct JointPayload: Encodable {
    let x: Double
    let y: Double
    let confidence: Double
}
