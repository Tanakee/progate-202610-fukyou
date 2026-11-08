import Observation
import SwiftUI
import UIKit

/// 曲のサムネイルから、再生バーに使う色を取り出す。取り出した色は URL ごとに覚える
@MainActor
@Observable
final class ArtworkColors {
    private(set) var colors: [URL: Color] = [:]
    private var loading: Set<URL> = []

    func color(for url: URL?) -> Color? {
        guard let url else { return nil }
        if let color = colors[url] { return color }
        load(url)
        return nil
    }

    private func load(_ url: URL) {
        guard !loading.contains(url) else { return }
        loading.insert(url)
        Task {
            defer { loading.remove(url) }
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data),
                  let color = Self.vivid(of: image) else { return }
            colors[url] = Color(color)
        }
    }

    /// 小さく縮めた画像の、彩度と明るさがある画素を平均する。
    /// ただの平均だと灰色や茶色にくすむので、鮮やかな画素を選び、明るさを少し持ち上げる
    nonisolated static func vivid(of image: UIImage) -> UIColor? {
        guard let cgImage = image.cgImage else { return nil }
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        var vivid: [(h: CGFloat, s: CGFloat, b: CGFloat)] = []
        var all: [(h: CGFloat, s: CGFloat, b: CGFloat)] = []
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let color = UIColor(red: CGFloat(pixels[i]) / 255, green: CGFloat(pixels[i + 1]) / 255,
                                blue: CGFloat(pixels[i + 2]) / 255, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
            color.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
            all.append((h, s, b))
            if s > 0.35 && b > 0.35 { vivid.append((h, s, b)) }
        }
        let picked = vivid.count >= 8 ? vivid : all
        guard !picked.isEmpty else { return nil }
        // 色相は円なので、ベクトルで平均する
        let x = picked.map { cos($0.h * 2 * .pi) * $0.s }.reduce(0, +)
        let y = picked.map { sin($0.h * 2 * .pi) * $0.s }.reduce(0, +)
        var hue = atan2(y, x) / (2 * .pi)
        if hue < 0 { hue += 1 }
        let saturation = picked.map(\.s).reduce(0, +) / CGFloat(picked.count)
        let brightness = picked.map(\.b).reduce(0, +) / CGFloat(picked.count)
        return UIColor(hue: hue, saturation: min(max(saturation, 0.35), 0.75), brightness: min(max(brightness, 0.7), 0.95), alpha: 1)
    }
}
