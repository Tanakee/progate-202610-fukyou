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
    @State private var artworkColors = ArtworkColors()
    /// 説明を見終えるまで、位置情報の許可を尋ねない
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    private let notificationDelegate = NotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        Theme.applyNavigationBarAppearance()
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
            Group {
                if hasCompletedOnboarding {
                    MainView()
                } else {
                    OnboardingView {
                        hasCompletedOnboarding = true
                    }
                }
            }
            .environment(session)
            .environment(auth)
            .environment(tracks)
            .environment(myBalloon)
            .environment(pops)
            .environment(artworkColors)
            .font(Theme.font(16))
            .tint(Theme.sky)
            .task { await auth.refresh() }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            // 起動と復帰のときに読み直す。切れていればつなぎ直す
            startServicesIfReady(phase: phase)
        }
        .onChange(of: hasCompletedOnboarding) { _, completed in
            guard completed else { return }
            startServicesIfReady(phase: scenePhase)
        }
    }

    private func startServicesIfReady(phase: ScenePhase) {
        guard hasCompletedOnboarding, phase == .active else { return }
        session.feed.start()
        session.location.start()
        session.start()
    }
}
