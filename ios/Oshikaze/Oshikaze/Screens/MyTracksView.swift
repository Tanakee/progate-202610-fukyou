import SwiftUI

/// 自分が追加した曲の一覧と、YouTube の URL からの追加
struct MyTracksView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(TrackStore.self) private var tracks
    @Environment(MyBalloonStore.self) private var myBalloon
    @State private var youtubeURL = ""
    @State private var isImporting = false
    @State private var errorMessage: String?

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
