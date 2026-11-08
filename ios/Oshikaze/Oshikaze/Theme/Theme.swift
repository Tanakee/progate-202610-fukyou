import SwiftUI
import UIKit

/// 推し風の見た目。画面の土台は「曲」ではなく「曲を運ぶ空と風船」を表し、
/// どんな曲が流れても浮かないよう、やわらかく主張しすぎない色にする。曲ごとの個性は再生バーの色で出す
enum Theme {
    /// ボタンなどの基本の色。空の青
    static let sky = Color(red: 0.29, green: 0.62, blue: 0.96)
    /// 回収（お気に入り）の色
    static let heart = Color(red: 1.0, green: 0.45, blue: 0.62)
    static let ink = Color(red: 0.22, green: 0.25, blue: 0.33)

    /// 風船の色。地図の落ち着いた色の上で映える、やわらかく明るい色
    static let balloonColors: [Color] = [
        Color(red: 1.00, green: 0.54, blue: 0.54), // コーラル
        Color(red: 1.00, green: 0.70, blue: 0.48), // ピーチ
        Color(red: 1.00, green: 0.85, blue: 0.40), // レモン
        Color(red: 0.49, green: 0.85, blue: 0.65), // ミント
        Color(red: 0.42, green: 0.83, blue: 0.88), // アクア
        Color(red: 0.48, green: 0.72, blue: 1.00), // そら
        Color(red: 0.66, green: 0.61, blue: 1.00), // ラベンダー
        Color(red: 0.84, green: 0.61, blue: 0.94), // ライラック
        Color(red: 1.00, green: 0.61, blue: 0.79), // ピンク
    ]

    static func balloonColor(for id: Int) -> Color {
        balloonColors[id % balloonColors.count]
    }

    // MARK: - 空の色

    /// 時間帯に合わせた空の色。地図の上の方に薄く重ねる
    static func skyColors(at date: Date = .now) -> [Color] {
        let hour = Calendar(identifier: .gregorian).component(.hour, from: date)
        switch hour {
        case 5..<9: // 朝
            return [Color(red: 1.00, green: 0.82, blue: 0.80), Color(red: 0.78, green: 0.89, blue: 1.00)]
        case 9..<16: // 昼
            return [Color(red: 0.62, green: 0.82, blue: 1.00), Color(red: 0.86, green: 0.94, blue: 1.00)]
        case 16..<19: // 夕方
            return [Color(red: 1.00, green: 0.66, blue: 0.48), Color(red: 1.00, green: 0.84, blue: 0.74)]
        default: // 夜
            return [Color(red: 0.16, green: 0.20, blue: 0.42), Color(red: 0.40, green: 0.38, blue: 0.66)]
        }
    }

    // MARK: - フォント

    /// やわらかい丸ゴシック。Dynamic Type に合わせて大きさが変わる
    enum Weight: String {
        case regular = "ZenMaruGothic-Regular"
        case medium = "ZenMaruGothic-Medium"
        case bold = "ZenMaruGothic-Bold"
    }

    static func font(_ size: CGFloat, _ weight: Weight = .medium, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(weight.rawValue, size: size, relativeTo: style)
    }

    /// SwiftUI の `.font` が届かないナビゲーションバーの文字にも、同じフォントを使う
    static func applyNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        if let title = UIFont(name: Weight.bold.rawValue, size: 17), let large = UIFont(name: Weight.bold.rawValue, size: 32) {
            appearance.titleTextAttributes = [.font: title, .foregroundColor: UIColor(ink)]
            appearance.largeTitleTextAttributes = [.font: large, .foregroundColor: UIColor(ink)]
        }
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
}

// MARK: - 部品

/// 白くふんわりしたカード。再生バーや吹き出しに使う
struct SoftCard: ViewModifier {
    var tint: Color = .white
    var cornerRadius: CGFloat = 26

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    // 文字が読みやすいよう、ほぼ白にする。曲ごとの色はふちと影にだけ、ほんのり出す
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.white.opacity(0.88))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(tint.opacity(0.35), lineWidth: 1.5)
                    }
                    .shadow(color: tint.opacity(0.25), radius: 14, y: 6)
            }
    }
}

extension View {
    func softCard(tint: Color = .white, cornerRadius: CGFloat = 26) -> some View {
        modifier(SoftCard(tint: tint, cornerRadius: cornerRadius))
    }

    /// 一覧やフォームの背景を、時間帯の空の色を白で薄めたグラデーションにする。行は白いカードのまま浮かせる
    func skyBackground() -> some View {
        scrollContentBackground(.hidden)
            .background {
                LinearGradient(colors: Theme.skyColors().map { $0.mix(with: .white, by: 0.55) },
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }
    }
}

/// 押すとぷにっと縮み、離すと弾んで戻る
struct BouncyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.45), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == BouncyButtonStyle {
    static var bouncy: BouncyButtonStyle { BouncyButtonStyle() }
}

/// 白い丸の中にアイコンを置いた丸ボタン
struct RoundIcon: View {
    let systemName: String
    var size: CGFloat = 46
    var color: Color = Theme.sky
    var filled = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(filled ? .white : color)
            .frame(width: size, height: size)
            .background(Circle().fill(filled ? AnyShapeStyle(color.gradient) : AnyShapeStyle(.white)))
            .shadow(color: color.opacity(0.35), radius: 8, y: 4)
    }
}

/// 白い丸みのある札。ボタンの見た目に使う。
/// 絵文字は丸ゴシックに入っておらず「?」になることがあるので、アイコンは SF Symbols を使う
struct PillLabel: View {
    let title: String
    let systemImage: String
    var color: Color = Theme.sky

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(color)
            Text(title).font(Theme.font(16, .bold, relativeTo: .headline))
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(Capsule().fill(.white))
        .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1.5))
        .shadow(color: color.opacity(0.3), radius: 10, y: 5)
    }
}
