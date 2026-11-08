import SwiftUI

/// 1行に収まらないときだけ、文字を横にゆっくり流す。収まるときは止めて表示する。
/// YouTube の動画名のような長い曲名でも、最後まで読めるようにする
struct MarqueeText: View {
    let text: String
    let font: Font

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    /// 流れる速さ（ポイント/秒）と、端で止まる時間
    private static let speed: CGFloat = 30
    private static let pause: Double = 1.5
    private static let gap: CGFloat = 40

    private var overflows: Bool { textWidth > containerWidth + 1 }

    var body: some View {
        // 置き場所の大きさは、ふつうの1行の文字で決める。流すときはこれを隠して上に重ねる
        Text(text)
            .font(font)
            .lineLimit(1)
            .opacity(overflows ? 0 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { containerWidth = $0 }
            // 本来の文字の幅は、レイアウトに影響しない背景で測る
            .background(alignment: .leading) {
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize()
                    .hidden()
                    .onGeometryChange(for: CGFloat.self, of: \.size.width) { textWidth = $0 }
            }
            .overlay(alignment: .leading) {
                if overflows {
                    scrolling
                }
            }
            .clipped()
            .accessibilityElement()
            .accessibilityLabel(text)
    }

    /// 同じ文字を間をあけて2つ並べ、1周分ずらしたら最初に戻す。端で少し止まる
    private var scrolling: some View {
        let cycle = textWidth + Self.gap
        let duration = Double(cycle / Self.speed)
        return TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration + Self.pause)
            let offset = t < Self.pause ? 0 : CGFloat(t - Self.pause) * Self.speed
            HStack(spacing: Self.gap) {
                Text(text)
                Text(text)
            }
            .font(font)
            .lineLimit(1)
            .fixedSize()
            .offset(x: -offset)
            .frame(width: containerWidth, alignment: .leading)
        }
        // 右端をふわっと消して、文字が途中で切れて見えないようにする
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.88),
                                     .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
    }
}
