import Foundation
import Observation
import os

/// 画面とファイルの両方に残すログ。ロック中に何が起きたかを、解除後に時刻つきで確かめるために使う。
@MainActor
@Observable
final class EventLog {
    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let text: String
    }

    private(set) var entries: [Entry] = []
    let fileURL = URL.documentsDirectory.appending(path: "spike-log.txt")

    private let logger = Logger(subsystem: "BackgroundSpike", category: "event")
    private static let maxEntries = 500
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "MM/dd HH:mm:ss.SSS"
        return formatter
    }()

    func add(_ text: String) {
        let entry = Entry(date: .now, text: text)
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast()
        }
        logger.info("\(text, privacy: .public)")
        appendToFile("\(Self.format(entry.date)) \(text)\n")
    }

    func clear() {
        entries.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
    }

    static func format(_ date: Date) -> String {
        formatter.string(from: date)
    }

    private func appendToFile(_ line: String) {
        let data = Data(line.utf8)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
    }
}
