import SwiftUI
import UIKit

/// 画面下のパチンコ。木のY字、伸びるゴム、受け皿、つやのある弾を描く。
/// 引いている間は飛ぶ向きと強さを点線で出し、放すとゴムがぶるんと戻る
struct SlingshotPad: View {
    /// 放したときの引いた量（画面のポイント）
    let onRelease: (CGSize) -> Void

    @State private var pull = CGSize.zero
    @State private var isDragging = false
    @State private var hasPulled = false
    /// 放した瞬間の引いた量と時刻。ここからゴムが揺れながら戻る
    @State private var release: (pull: CGSize, at: Date)?
    @State private var lastLevel = 0

    static let maxPull: CGFloat = 130
    private static let size = CGSize(width: 220, height: 250)
    private static let leftTip = CGPoint(x: 58, y: 78)
    private static let rightTip = CGPoint(x: 162, y: 78)
    /// 弾の休んでいる位置
    private static let rest = CGPoint(x: 110, y: 82)
    private static let joint = CGPoint(x: 110, y: 150)
    private static let bottom = CGPoint(x: 110, y: 236)

    private static let woodLight = Color(red: 0.89, green: 0.68, blue: 0.45)
    private static let woodDark = Color(red: 0.72, green: 0.48, blue: 0.29)
    private static let ammo = Theme.balloonColors[8]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, _ in
                draw(in: &context, at: timeline.date)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .overlay(alignment: .bottom) {
            if !hasPulled {
                Text("弾を下に引いて、放そう")
                    .font(Theme.font(13, .bold, relativeTo: .caption))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.9)))
                    .offset(y: 18)
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    isDragging = true
                    release = nil
                    pull = Self.limited(value.translation)
                    tickHaptics()
                }
                .onEnded { _ in
                    isDragging = false
                    let released = pull
                    release = (released, .now)
                    pull = .zero
                    lastLevel = 0
                    if hypot(released.width, released.height) > 20 {
                        withAnimation { hasPulled = true }
                    }
                    onRelease(released)
                }
        )
        .accessibilityLabel("パチンコ。下に引いて放すと、狙った方向に飛びます")
    }

    // MARK: - 描画

    private func draw(in context: inout GraphicsContext, at date: Date) {
        let current = currentPull(at: date)
        let stretch = min(hypot(current.width, current.height) / Self.maxPull, 1)
        // 触っていない間は、弾がふわふわ揺れて、引けることを伝える
        let bob = isDragging || release != nil ? 0 : sin(date.timeIntervalSinceReferenceDate * 3) * 3
        let stone = CGPoint(x: Self.rest.x + current.width, y: Self.rest.y + current.height + bob)

        if isDragging && stretch > 0.08 {
            drawAimGuide(in: &context, pull: current, stretch: stretch)
        }
        // 引いた弾は本体より手前にあるので、本体を先に描き、ゴムと弾を上に重ねる
        drawFork(in: &context)
        drawBand(in: &context, from: Self.leftTip, to: stone, stretch: stretch)
        drawBand(in: &context, from: Self.rightTip, to: stone, stretch: stretch)
        drawPouch(in: &context, at: stone, pull: current)
        drawAmmo(in: &context, at: stone)
    }

    /// 木のY字と、ゴムを結んだ先端のこぶ
    private func drawFork(in context: inout GraphicsContext) {
        var fork = Path()
        fork.move(to: Self.bottom)
        fork.addLine(to: Self.joint)
        fork.addQuadCurve(to: Self.leftTip, control: CGPoint(x: 70, y: 140))
        fork.move(to: Self.joint)
        fork.addQuadCurve(to: Self.rightTip, control: CGPoint(x: 150, y: 140))

        let wood = GraphicsContext.Shading.linearGradient(Gradient(colors: [Self.woodLight, Self.woodDark]),
                                                          startPoint: CGPoint(x: 40, y: 0), endPoint: CGPoint(x: 180, y: 250))
        var shadow = context
        shadow.addFilter(.shadow(color: .black.opacity(0.25), radius: 6, y: 4))
        shadow.stroke(fork, with: wood, style: StrokeStyle(lineWidth: 22, lineCap: .round, lineJoin: .round))
        // 左側に細い光を入れて、丸みのある木に見せる
        context.stroke(fork.offsetBy(dx: -4, dy: -2), with: .color(.white.opacity(0.28)),
                       style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))

        // ゴムを結んだ先端のこぶ
        for tip in [Self.leftTip, Self.rightTip] {
            context.fill(Path(ellipseIn: CGRect(x: tip.x - 9, y: tip.y - 9, width: 18, height: 18)), with: .color(Self.woodDark))
            context.fill(Path(ellipseIn: CGRect(x: tip.x - 6, y: tip.y - 7, width: 7, height: 6)), with: .color(.white.opacity(0.4)))
        }
    }

    /// ゴムは引くほど細く伸び、色が濃くなる
    private func drawBand(in context: inout GraphicsContext, from tip: CGPoint, to stone: CGPoint, stretch: CGFloat) {
        var band = Path()
        band.move(to: tip)
        band.addLine(to: stone)
        let color = Theme.heart.mix(with: Color(red: 0.85, green: 0.1, blue: 0.3), by: stretch * 0.6)
        context.stroke(band, with: .color(color), style: StrokeStyle(lineWidth: 8 - 4.5 * stretch, lineCap: .round))
    }

    /// 弾を包む受け皿。引く向きに合わせて傾ける
    private func drawPouch(in context: inout GraphicsContext, at stone: CGPoint, pull: CGSize) {
        let angle = pull == .zero ? 0 : atan2(pull.height, pull.width) - .pi / 2
        let pouch = Path(roundedRect: CGRect(x: -24, y: 4, width: 48, height: 14), cornerRadius: 7)
            .applying(CGAffineTransform(rotationAngle: angle))
            .applying(CGAffineTransform(translationX: stone.x, y: stone.y))
        context.fill(pouch, with: .color(Self.woodDark.mix(with: .black, by: 0.25)))
    }

    /// つやのあるパステルの弾
    private func drawAmmo(in context: inout GraphicsContext, at stone: CGPoint) {
        let radius: CGFloat = 16
        let ball = Path(ellipseIn: CGRect(x: stone.x - radius, y: stone.y - radius, width: radius * 2, height: radius * 2))
        var shadow = context
        shadow.addFilter(.shadow(color: Self.ammo.opacity(0.6), radius: 6))
        shadow.fill(ball, with: .radialGradient(Gradient(colors: [Self.ammo.mix(with: .white, by: 0.6), Self.ammo]),
                                                center: CGPoint(x: stone.x - 5, y: stone.y - 6), startRadius: 1, endRadius: radius * 1.3))
        context.fill(Path(ellipseIn: CGRect(x: stone.x - 9, y: stone.y - 11, width: 8, height: 6)), with: .color(.white.opacity(0.85)))
    }

    /// 飛んでいく向きと強さの目安。引いた向きの逆へ、強いほど遠くまで点を並べ、少し落ちる弧にする
    private func drawAimGuide(in context: inout GraphicsContext, pull: CGSize, stretch: CGFloat) {
        let length = hypot(pull.width, pull.height)
        let direction = CGPoint(x: -pull.width / length, y: -pull.height / length)
        let spacing = 10 + 16 * stretch
        for index in 1...7 {
            let i = CGFloat(index)
            let point = CGPoint(x: Self.rest.x + direction.x * spacing * i,
                                y: Self.rest.y + direction.y * spacing * i + i * i * 1.2)
            let radius = 5 - i * 0.45
            context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                         with: .color(.white.opacity(0.95 - i * 0.11)))
        }
    }

    // MARK: - 動き

    /// 放したあとは、ゴムが揺れながら戻る（減衰する振動）
    private func currentPull(at date: Date) -> CGSize {
        if isDragging { return pull }
        guard let release else { return .zero }
        let t = date.timeIntervalSince(release.at)
        guard t < 0.7 else { return .zero }
        let factor = exp(-t * 7) * cos(t * 28)
        return CGSize(width: release.pull.width * factor, height: release.pull.height * factor)
    }

    /// 引く強さが3段階のどこかを超えるたびに、軽く振動させる
    private func tickHaptics() {
        let level = Int(min(hypot(pull.width, pull.height) / Self.maxPull, 1) * 3)
        guard level > lastLevel else {
            lastLevel = level
            return
        }
        lastLevel = level
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.4 + 0.2 * CGFloat(level))
    }

    /// パチンコは下に引いて撃つもの。上には引けないようにし、横は下に引いた量までに抑える。
    /// 上や真横に引いても撃てると、下向きや真横へ飛んで、あらぬ方向に見える
    private static func limited(_ translation: CGSize) -> CGSize {
        let down = max(translation.height, 0)
        let side = min(max(translation.width, -down), down)
        let length = hypot(side, down)
        guard length > maxPull else { return CGSize(width: side, height: down) }
        return CGSize(width: side / length * maxPull, height: down / length * maxPull)
    }
}
