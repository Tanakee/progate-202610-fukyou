import SwiftUI
import UserNotifications

struct ContentView: View {
    @Environment(SpikeModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("serverURL") private var serverURL = "ws://192.168.0.10:8080"
    @State private var notificationStatus = "未確認"

    var body: some View {
        NavigationStack {
            Form {
                connectionSection
                playbackSection
                notificationSection
                logSection
            }
            .navigationTitle("BG検証")
        }
        .task { await refreshNotificationStatus() }
        .onChange(of: scenePhase) { _, phase in
            model.log.add("画面の状態: \(Self.label(of: phase))")
        }
    }

    private var connectionSection: some View {
        Section("WebSocket") {
            TextField("ws://", text: $serverURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            LabeledContent("状態", value: model.socket.state.rawValue)
            LabeledContent("受信数", value: "\(model.socket.receivedCount)")
            if model.socket.state == .disconnected {
                Button("接続する") { model.socket.connect(to: serverURL) }
            } else {
                Button("切断する", role: .destructive) { model.socket.disconnect() }
            }
        }
    }

    private var playbackSection: some View {
        Section("再生") {
            LabeledContent("再生中の曲", value: model.audio.nowPlaying)
            LabeledContent("状態", value: model.audio.isPlaying ? "再生中" : "停止中")
            Button("2曲を連続再生") { model.audio.playTracks() }
            Button("無音ループ") { model.audio.playSilence() }
            Button("停止", role: .destructive) { model.audio.stop() }
        }
    }

    private var notificationSection: some View {
        Section("通知") {
            LabeledContent("許可", value: notificationStatus)
            Button("通知を許可する") {
                Task {
                    let granted = await Notifier.requestAuthorization()
                    model.log.add("通知の許可: \(granted ? "許可" : "拒否")")
                    await refreshNotificationStatus()
                }
            }
        }
    }

    private var logSection: some View {
        Section {
            ForEach(model.log.entries) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(EventLog.format(entry.date))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(entry.text)
                        .font(.footnote)
                }
            }
        } header: {
            HStack {
                Text("ログ")
                Spacer()
                ShareLink(item: model.log.fileURL) { Image(systemName: "square.and.arrow.up") }
                Button("消去") { model.log.clear() }
            }
        }
    }

    private func refreshNotificationStatus() async {
        notificationStatus = switch await Notifier.authorizationStatus() {
        case .authorized, .provisional, .ephemeral: "許可済み"
        case .denied: "拒否"
        case .notDetermined: "未確認"
        @unknown default: "不明"
        }
    }

    private static func label(of phase: ScenePhase) -> String {
        switch phase {
        case .active: "前面"
        case .inactive: "非アクティブ"
        case .background: "バックグラウンド"
        @unknown default: "不明"
        }
    }
}
