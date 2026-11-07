import SwiftUI

@main
struct OshikazeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var auth = AuthStore()
    @State private var tracks: TrackStore
    @State private var session: ListeningSession

    init() {
        let tracks = TrackStore()
        _tracks = State(initialValue: tracks)
        _session = State(initialValue: ListeningSession(feed: BalloonFeed(), location: LocationProvider(),
                                                        playback: PlaybackController(), tracks: tracks))
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(session)
                .environment(auth)
                .environment(tracks)
                .task { await auth.refresh() }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            // 起動と復帰のときに読み直す。切れていればつなぎ直す
            guard phase == .active else { return }
            session.feed.start()
            session.location.start()
            session.start()
        }
    }
}
