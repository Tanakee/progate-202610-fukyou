import Foundation

struct Track: Equatable {
    let id: Int
    let title: String
    let artist: String
    let audioURL: URL
}

/// 曲IDから曲名と音源を引く。
/// `GET /tracks/:id` ができるまでは、アプリに同梱した仮の音源を返す
enum TrackCatalog {
    private static let placeholderTitles = ["夜明けのメロディ", "君と見た星", "サイダー", "雨上がりの坂道", "ネオンライト",
                                            "春風ステップ", "眠れない夜に", "放課後のリズム", "海辺のワルツ", "群青"]

    static func track(id: Int) -> Track {
        let file = id.isMultiple(of: 2) ? "track2" : "track1"
        return Track(id: id,
                     title: placeholderTitles[id % placeholderTitles.count],
                     artist: "仮の音源",
                     audioURL: Bundle.main.url(forResource: file, withExtension: "mp3")!)
    }

    static let silenceURL = Bundle.main.url(forResource: "silence", withExtension: "mp3")!
}
