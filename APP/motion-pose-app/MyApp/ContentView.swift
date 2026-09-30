import SwiftUI

private enum DetectionMode: String, CaseIterable, Identifiable {
    case motion = "三軸數值"
    case bodyPose = "身體關節"

    var id: Self { self }
}

struct ContentView: View {
    @StateObject private var telemetry = TelemetryClient()
    @State private var mode: DetectionMode = UIDevice.current.userInterfaceIdiom == .pad ? .bodyPose : .motion

    var body: some View {
        VStack(spacing: 0) {
            Picker("偵測模式", selection: $mode) {
                ForEach(DetectionMode.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top)

            if mode == .motion {
                MotionDashboardView(telemetry: telemetry)
            } else {
                BodyPoseView(telemetry: telemetry)
            }

            DisclosureGroup("Django API 設定") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("https://example.com/api/telemetry/", text: $telemetry.endpoint)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .textFieldStyle(.roundedBorder)

                    Toggle("傳送數值到 Django", isOn: $telemetry.isEnabled)

                    Text("手機熱點內可填 http://Mac的私人IP:8000/api/telemetry/；公開伺服器請用 HTTPS。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text(telemetry.status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
            .padding()
            .background(.regularMaterial)
        }
    }
}
