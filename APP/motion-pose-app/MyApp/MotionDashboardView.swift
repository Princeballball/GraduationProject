import ARKit
import SwiftUI

struct MotionDashboardView: View {
    @ObservedObject var telemetry: TelemetryClient
    @StateObject private var tracker = PositionTracker()
    @StateObject private var orientation = OrientationTracker()
    @Environment(\.scenePhase) private var scenePhase
    @State private var shouldTrack = true

    private var isMeasuring: Bool { tracker.isRunning || orientation.isRunning }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("手機位置與姿態")
                    .font(.largeTitle.bold())

                Text("三軸位置")
                    .font(.title2.bold())

                Text(tracker.status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                CameraPreview(session: tracker.session)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                valueRow("X", description: "水平左右", value: tracker.reading?.x, unit: "m", digits: 3, color: .red)
                valueRow("Y", description: "向上為正", value: tracker.reading?.y, unit: "m", digits: 3, color: .green)
                valueRow("Z", description: "水平前後", value: tracker.reading?.z, unit: "m", digits: 3, color: .blue)

                Text("角度")
                    .font(.title2.bold())

                Text(orientation.status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                valueRow("翻滾 Roll", description: "左右側傾", value: orientation.reading?.roll, unit: "°", digits: 1, color: .red)
                valueRow("俯仰 Pitch", description: "前後傾斜", value: orientation.reading?.pitch, unit: "°", digits: 1, color: .green)
                valueRow("偏航 Yaw", description: "水平轉向", value: orientation.reading?.yaw, unit: "°", digits: 1, color: .blue)

                Text("角速度")
                    .font(.title2.bold())

                valueRow("X 軸", description: "繞手機 X 軸旋轉", value: orientation.reading?.rotationX, unit: "°/s", digits: 1, color: .red)
                valueRow("Y 軸", description: "繞手機 Y 軸旋轉", value: orientation.reading?.rotationY, unit: "°/s", digits: 1, color: .green)
                valueRow("Z 軸", description: "繞手機 Z 軸旋轉", value: orientation.reading?.rotationZ, unit: "°/s", digits: 1, color: .blue)

                HStack {
                    Button(isMeasuring ? "暫停" : "開始") {
                        shouldTrack = !isMeasuring
                        updateTracking()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!tracker.isAvailable && !orientation.isAvailable)

                    Button("重新設為原點") { tracker.resetOrigin() }
                        .buttonStyle(.bordered)
                        .disabled(!tracker.isRunning || tracker.reading == nil)
                }

                Text("位置以啟動點為原點，向上移動時 Y 增加。角度是相對姿態參考方向的度數，偏航角不代表羅盤方位；角速度是當下旋轉快慢，單位為度／秒。位置追蹤需要相機，光線不足時可能漂移。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: 540)
            .frame(maxWidth: .infinity)
        }
        .onAppear { updateTracking() }
        .onChange(of: scenePhase) { _, _ in updateTracking() }
        .onReceive(tracker.$reading) { _ in sendReading() }
        .onReceive(orientation.$reading) { _ in sendReading() }
        .onDisappear {
            tracker.stop()
            orientation.stop()
        }
    }

    private func valueRow(_ name: String, description: String, value: Double?, unit: String, digits: Int, color: Color) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text("\(name) 軸")
                    .font(.headline)
                    .foregroundStyle(color)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(value.map { String(format: "%+.*f", digits, $0) } ?? "—") \(unit)")
                .font(.system(.title3, design: .monospaced))
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func updateTracking() {
        if scenePhase == .active && shouldTrack {
            tracker.start()
            orientation.start()
        } else {
            tracker.stop()
            orientation.stop()
        }
    }

    private func sendReading() {
        guard tracker.isRunning || orientation.isRunning else { return }
        telemetry.sendMotion(position: tracker.reading, orientation: orientation.reading)
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = session
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {}
}
