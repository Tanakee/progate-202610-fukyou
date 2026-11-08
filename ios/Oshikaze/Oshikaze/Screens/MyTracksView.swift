import SwiftUI

/// 自分が追加した曲の一覧と、YouTube の URL からの追加
struct MyTracksView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(TrackStore.self) private var tracks
    @Environment(MyBalloonStore.self) private var myBalloon
    @Environment(ListeningSession.self) private var session
    @State private var youtubeURL = ""
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var confirmsLanding = false
    @State private var isLanding = false
    @State private var demoMessage: String?
    @State private var isRunningDemo = false

    var body: some View {
        List {
            Section {
                TextField("https://www.youtube.com/watch?v=…", text: $youtubeURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(isImporting)
                Button {
                    Task { await importTrack() }
                } label: {
                    if isImporting {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("曲を取り込んでいます（1分ほどかかります）")
                        }
                    } else {
                        Text("曲を追加する")
                    }
                }
                .disabled(isImporting || youtubeURL.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("YouTube の URL から追加")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }

            if let balloon = myBalloon.balloon {
                Section("飛んでいる風船") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tracks.myTracks.first { $0.id == balloon.trackID }?.title ?? "自分の曲").font(.headline)
                        Text("\(balloon.originLabel)から・\(balloon.playCount)回聴かれました")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Button("風船を下ろす", role: .destructive) {
                        confirmsLanding = true
                    }
                    .disabled(isLanding)
                    .confirmationDialog("風船を下ろしますか？", isPresented: $confirmsLanding, titleVisibility: .visible) {
                        Button("下ろす", role: .destructive) {
                            Task { await land(balloon) }
                        }
                    } message: {
                        Text("みんなの空から消えて、旅が終わります。下ろしたあとは、次の風船を飛ばせます")
                    }
                }
            }

            Section("自分の曲") {
                if tracks.myTracks.isEmpty {
                    Text("まだ曲がありません").foregroundStyle(.secondary)
                }
                ForEach(tracks.myTracks) { track in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title).font(.headline)
                        Text(track.artist).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button("今日の回収をリセットする") {
                    Task { await resetFavoriteLimit() }
                }
                .disabled(isRunningDemo)
                Button("風船を日本各地に配置する") {
                    Task { await repositionBalloons() }
                }
                .disabled(isRunningDemo)
                if let demoMessage {
                    Text(demoMessage).foregroundStyle(.secondary)
                }
            } header: {
                Text("デモ用")
            } footer: {
                Text("開発環境のサーバーでだけ使えます")
            }

            Section {
                if let email = auth.user?.email {
                    LabeledContent("ログイン中", value: email)
                }
                Button("ログアウト", role: .destructive) {
                    Task {
                        await auth.logOut()
                        tracks.clearMyTracks()
                        myBalloon.clear()
                    }
                }
            }
        }
        .navigationTitle("自分の曲")
        .skyBackground()
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            try await tracks.loadMyTracks(with: auth)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetFavoriteLimit() async {
        isRunningDemo = true
        defer { isRunningDemo = false }
        do {
            let result: [String: Int] = try await auth.client.send(.post, "test_reset_favorite_limit")
            demoMessage = result["reset_count"] == 0 ? "今日はまだ回収していません" : "今日の回収をリセットしました。もう1曲回収できます"
        } catch {
            auth.handle(error)
            demoMessage = error.localizedDescription
        }
    }

    private func repositionBalloons() async {
        isRunningDemo = true
        defer { isRunningDemo = false }
        do {
            let result: [String: Int] = try await auth.client.send(.post, "test_reposition_balloons")
            demoMessage = "\(result["updated_count"] ?? 0)個の風船を日本各地に配置しました"
        } catch {
            auth.handle(error)
            demoMessage = error.localizedDescription
        }
    }

    private func land(_ balloon: MyBalloon) async {
        isLanding = true
        defer { isLanding = false }
        do {
            try await myBalloon.land(with: auth)
            session.feed.remove(balloon.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importTrack() async {
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }
        do {
            _ = try await tracks.addTrack(youtubeURL: youtubeURL.trimmingCharacters(in: .whitespaces), with: auth)
            youtubeURL = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 右上のボタンから開く。ログインしていなければログイン画面を出す
struct AccountSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if auth.isSignedIn {
                    MyPageView()
                } else {
                    LoginView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}
