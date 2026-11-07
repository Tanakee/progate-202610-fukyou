import SwiftUI

@main
struct OshikazeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = ListeningSession(feed: BalloonFeed(), location: LocationProvider(), playback: PlaybackController())

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(session)
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
