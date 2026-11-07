import AVFoundation
import SwiftUI

/// 左上のボタンから開くマイページ。お気に入り・旅の記録・自分の曲をタブで切り替える
struct MyPageView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case favorites = "お気に入り"
        case journeys = "旅の記録"
        case tracks = "自分の曲"
        var id: Self { self }
    }

    @State private var tab = Tab.favorites

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)
            switch tab {
            case .favorites: FavoritesList()
            case .journeys: JourneysList()
            case .tracks: MyTracksView()
            }
        }
        .navigationTitle("マイページ")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 回収した曲。タップするとその場で試聴できる
private struct FavoritesList: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ListeningSession.self) private var session
    @State private var favorites: [Favorite] = []
    @State private var errorMessage: String?
    @State private var preview: AVPlayer?
    @State private var previewingID: Int?
    @State private var wasListening = false

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            if favorites.isEmpty && errorMessage == nil {
                ContentUnavailableView("まだお気に入りがありません",
                                       systemImage: "heart",
                                       description: Text("流れてきた曲を回収すると、ここに残ります。回収は1日1回です。"))
            }
            ForEach(favorites) { favorite in
                Button {
                    togglePreview(favorite)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(favorite.track.title).font(.headline).foregroundStyle(.primary)
                            Text("\(favorite.track.artist)・\(favorite.collectedOn)に回収")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: previewingID == favorite.id ? "stop.circle.fill" : "play.circle")
                            .font(.title2)
                    }
                }
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .onDisappear { stopPreview() }
    }

    private func load() async {
        do {
            favorites = try await auth.client.send(.get, "me/favorites")
            errorMessage = nil
        } catch {
            auth.handle(error)
            errorMessage = error.localizedDescription
        }
    }

    /// 地図の曲と重ならないよう、試聴の間は地図の再生を止め、終わったら戻す
    private func togglePreview(_ favorite: Favorite) {
        if previewingID == favorite.id {
            stopPreview()
            return
        }
        if preview == nil {
            wasListening = session.playback.isListening
            session.playback.setListening(false)
        }
        preview?.pause()
        let player = AVPlayer(url: favorite.track.mp3URL)
        player.play()
        preview = player
        previewingID = favorite.id
    }

    private func stopPreview() {
        guard let preview else { return }
        preview.pause()
        self.preview = nil
        previewingID = nil
        if wasListening {
            session.playback.setListening(true)
        }
    }
}

/// 飛ばした風船の旅の記録をカードで並べる
private struct JourneysList: View {
    @Environment(AuthStore.self) private var auth
    @State private var journeys: [Journey] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            if journeys.isEmpty && errorMessage == nil {
                ContentUnavailableView("まだ旅の記録がありません",
                                       systemImage: "map",
                                       description: Text("飛ばした風船が回収されるか、海や国外へ出ると、旅の記録が届きます。"))
            }
            ForEach(journeys) { journey in
                VStack(alignment: .leading, spacing: 8) {
                    Label(journey.endDescription, systemImage: journey.wasCollected ? "heart.fill" : "wind")
                        .font(.headline)
                    HStack(spacing: 16) {
                        Label(journey.durationText, systemImage: "clock")
                        Label("\(journey.playCount)回聴かれた", systemImage: "headphones")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            journeys = try await auth.client.send(.get, "me/journeys")
            errorMessage = nil
        } catch {
            auth.handle(error)
            errorMessage = error.localizedDescription
        }
    }
}
