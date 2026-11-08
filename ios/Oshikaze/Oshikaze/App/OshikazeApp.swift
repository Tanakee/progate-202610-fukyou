import SwiftUI
import UserNotifications

@main
struct OshikazeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var auth: AuthStore
    @State private var tracks: TrackStore
    @State private var myBalloon: MyBalloonStore
    @State private var pops: PopStore
    @State private var session: ListeningSession
    private let notificationDelegate = NotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        let auth = AuthStore()
        let tracks = TrackStore()
        let myBalloon = MyBalloonStore()
        let pops = PopStore()
        _auth = State(initialValue: auth)
        _tracks = State(initialValue: tracks)
        _myBalloon = State(initialValue: myBalloon)
        _pops = State(initialValue: pops)
        _session = State(initialValue: ListeningSession(feed: BalloonFeed(), location: LocationProvider(),
                                                        playback: PlaybackController(), tracks: tracks,
                                                        auth: auth, myBalloon: myBalloon, pops: pops))
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(session)
                .environment(auth)
                .environment(tracks)
                .environment(myBalloon)
                .environment(pops)
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
