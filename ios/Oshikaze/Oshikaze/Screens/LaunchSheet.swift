import SwiftUI

/// 自分の曲を選んで、現在地から風船を飛ばす
struct LaunchSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(TrackStore.self) private var tracks
    @Environment(MyBalloonStore.self) private var myBalloon
    @Environment(ListeningSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var launchingTrackID: Int?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if auth.isSignedIn {
                    trackList
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

    private var trackList: some View {
        List {
            Section {
                ForEach(tracks.myTracks) { track in
                    Button {
                        Task { await launch(track) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title).font(.headline).foregroundStyle(.primary)
                                Text(track.artist).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if launchingTrackID == track.id { ProgressView() }
                        }
                    }
                    .disabled(launchingTrackID != nil)
                }
                NavigationLink("YouTube の URL から曲を追加する") {
                    MyTracksView()
                }
            } header: {
                Text("飛ばす曲を選ぶ")
            } footer: {
                Text("現在地を約1kmの精度にぼかして、そこから飛ばします。正確な現在地は送りません。")
            }
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("風船を飛ばす")
        .task {
            do {
                try await tracks.loadMyTracks(with: auth)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func launch(_ track: Track) async {
        guard let here = session.location.coordinate else {
            errorMessage = "現在地がまだ取れていません。少し待ってからもう一度お試しください"
            return
        }
        launchingTrackID = track.id
        errorMessage = nil
        defer { launchingTrackID = nil }
        do {
            try await myBalloon.launch(track, from: here, with: auth)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
