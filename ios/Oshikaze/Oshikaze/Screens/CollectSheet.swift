import SwiftUI

/// 回収する風船。確認を出したときの風船と曲を覚えておく
struct CollectTarget: Identifiable {
    let balloonID: Int
    let track: Track
    let color: Color
    var id: Int { balloonID }
}

/// 回収の確認。回収できたらハートがはじけて、少しして閉じる
struct CollectSheet: View {
    let target: CollectTarget

    @Environment(ListeningSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var phase = Phase.confirm

    private enum Phase: Equatable {
        case confirm, sending, done
        case failed(String)
    }

    var body: some View {
        VStack(spacing: 14) {
            artwork
                .padding(.top, 8)
            VStack(spacing: 6) {
                Text(heading)
                    .font(Theme.font(20, .bold, relativeTo: .title3))
                    .foregroundStyle(Theme.ink)
                MarqueeText(text: target.track.title, font: Theme.font(15, .medium))
                    .foregroundStyle(Theme.ink.opacity(0.8))
                    .frame(maxWidth: 280)
                    .fixedSize(horizontal: false, vertical: true)
                Text(target.track.artist)
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.ink.opacity(0.55))
            }
            Text(note)
                .font(Theme.font(13))
                .foregroundStyle(caption)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            buttons
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: phase)
        .presentationDetents([.height(400)])
        .presentationCornerRadius(32)
        .presentationBackground {
            LinearGradient(colors: [target.color.mix(with: .white, by: 0.82), .white], startPoint: .top, endPoint: .bottom)
        }
        .interactiveDismissDisabled(phase == .sending)
    }

    private var heading: String {
        switch phase {
        case .confirm, .sending: "今日の1曲にする？"
        case .done: "回収しました！"
        case .failed: "回収できませんでした"
        }
    }

    private var note: String {
        switch phase {
        case .confirm, .sending: "回収は1日1回。風船はみんなの空から消えて、\nあなたのお気に入りに残ります"
        case .done: "マイページのお気に入りから、いつでも聴けます"
        case .failed(let message): message
        }
    }

    private var caption: Color {
        if case .failed = phase { return Theme.heart }
        return Theme.ink.opacity(0.6)
    }

    /// 曲の色の丸に風船（サムネイルがあればその画像）。回収できたらハートがはじける
    private var artwork: some View {
        ZStack {
            Circle().fill(target.color.gradient)
            if let url = target.track.thumbnailURL {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { balloonIcon }
            } else {
                balloonIcon
            }
        }
        .frame(width: 92, height: 92)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white, lineWidth: 4))
        .shadow(color: target.color.opacity(0.45), radius: 12, y: 6)
        .scaleEffect(phase == .done ? 1.08 : 1)
        .overlay {
            if phase == .done {
                HeartBurst()
            }
        }
    }

    private var balloonIcon: some View {
        Image(systemName: "balloon.fill")
            .font(.system(size: 38, weight: .bold))
            .foregroundStyle(.white)
    }

    @ViewBuilder
    private var buttons: some View {
        switch phase {
        case .confirm, .sending:
            HStack(spacing: 12) {
                Button("やめておく") { dismiss() }
                    .font(Theme.font(16, .bold))
                    .foregroundStyle(Theme.ink.opacity(0.6))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .disabled(phase == .sending)
                Button {
                    Task { await collect() }
                } label: {
                    HStack(spacing: 6) {
                        if phase == .sending {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "heart.fill")
                        }
                        Text("回収する")
                    }
                    .font(Theme.font(16, .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Capsule().fill(Theme.heart.gradient))
                    .shadow(color: Theme.heart.opacity(0.4), radius: 8, y: 4)
                }
                .buttonStyle(.bouncy)
                .disabled(phase == .sending)
            }
        case .done:
            EmptyView()
        case .failed:
            Button("閉じる") { dismiss() }
                .font(Theme.font(16, .bold))
                .foregroundStyle(Theme.ink.opacity(0.7))
                .frame(maxWidth: .infinity, minHeight: 50)
        }
    }

    private func collect() async {
        phase = .sending
        do {
            _ = try await session.collect(balloonID: target.balloonID)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            phase = .done
            try? await Task.sleep(for: .seconds(1.8))
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            phase = .failed(error.localizedDescription)
        }
    }
}

/// 中心から小さなハートがぱっと広がって消える
private struct HeartBurst: View {
    @State private var burst = false
    private static let count = 10

    var body: some View {
        ZStack {
            ForEach(0..<Self.count, id: \.self) { index in
                let angle = Double(index) / Double(Self.count) * 2 * .pi
                Image(systemName: "heart.fill")
                    .font(.system(size: index.isMultiple(of: 2) ? 16 : 11))
                    .foregroundStyle(index.isMultiple(of: 3) ? Theme.balloonColors[2] : Theme.heart)
                    .offset(x: burst ? cos(angle) * 78 : 0, y: burst ? sin(angle) * 78 : 0)
                    .scaleEffect(burst ? 1 : 0.2)
                    .opacity(burst ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { burst = true }
        }
    }
}
