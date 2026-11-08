import SwiftUI

/// 初めて開いた人に、推し風でできることを3枚で伝える全画面の説明
struct OnboardingView: View {
    let finish: () -> Void

    @State private var page = 0

    private let slides = [
        OnboardingSlide(
            symbol: "balloon.2.fill",
            color: Theme.balloonColors[0],
            title: "好きな曲を\n風船に乗せよう",
            message: "聴いている曲を、あなただけの\n風船に乗せて空へ放とう。"
        ),
        OnboardingSlide(
            symbol: "wind",
            color: Theme.sky,
            title: "風に乗って\n日本中を旅する",
            message: "風船は実際の風に流されるよ。\n近くを漂う曲も聴いてみよう。"
        ),
        OnboardingSlide(
            symbol: "heart.fill",
            color: Theme.heart,
            title: "好きな曲を\n見つけにいこう",
            message: "好きな曲は1日1回だけ回収。\n苦手な曲は空を見上げて割れるよ。"
        )
    ]

    var body: some View {
        ZStack {
            LinearGradient(colors: Theme.skyColors().map { $0.mix(with: .white, by: 0.18) },
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("スキップ", action: finish)
                        .font(Theme.font(16, .bold, relativeTo: .headline))
                        .foregroundStyle(Theme.ink.opacity(0.7))
                        .padding(12)
                        .accessibilityHint("説明を閉じて地図を開きます")
                }
                .padding(.horizontal, 16)

                TabView(selection: $page) {
                    ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                        slide
                            .tag(index)
                            .padding(.horizontal, 28)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 8) {
                    ForEach(slides.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? Theme.sky : .white.opacity(0.75))
                            .frame(width: index == page ? 28 : 9, height: 9)
                            .animation(.spring(response: 0.3), value: page)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("全3ページ中、\(page + 1)ページ目")

                Button {
                    if page == slides.count - 1 {
                        finish()
                    } else {
                        withAnimation { page += 1 }
                    }
                } label: {
                    Text(page == slides.count - 1 ? "はじめる" : "つぎへ")
                        .font(Theme.font(18, .bold, relativeTo: .headline))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(.white)
                        .background(Capsule().fill(Theme.sky.gradient))
                        .shadow(color: Theme.sky.opacity(0.35), radius: 10, y: 5)
                }
                .buttonStyle(.bouncy)
                .padding(.horizontal, 32)
                .padding(.top, 25)
                .padding(.bottom, 38)
                .accessibilityHint(page == slides.count - 1 ? "説明を終えて地図を開きます" : "次の説明へ進みます")
            }
        }
    }
}

private struct OnboardingSlide: View {
    let symbol: String
    let color: Color
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle()
                    .fill(color.opacity(0.18))
                    .frame(width: 205, height: 205)
                Image(systemName: symbol)
                    .font(.system(size: 88, weight: .medium, design: .rounded))
                    .foregroundStyle(color.gradient)
                    .symbolEffect(.bounce, options: .repeating)
            }
            .accessibilityHidden(true)
            VStack(spacing: 16) {
                Text(title)
                    .font(Theme.font(28, .bold, relativeTo: .title))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.ink)
                Text(message)
                    .font(Theme.font(17, relativeTo: .body))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.ink.opacity(0.76))
                    .lineSpacing(5)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity)
            .softCard(tint: color)
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    OnboardingView(finish: {})
}
