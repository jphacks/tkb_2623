//
//  MascotAnimationView.swift
//  GourmetShareMap
//

import SwiftUI
import UIKit

/// まんぷく先生の表示。レベルごとの画像をコマ送りでループする。
/// Assetに画像が入っていない段階では仮描き（`MascotPlaceholderView`）を出すので、
/// 画像が届いたら Asset に `mascot_lv2_01` などの名前で入れるだけで切り替わる。
struct MascotAnimationView: View {
    let level: MascotLevel
    /// 1秒あたりのコマ数。実機を見ながら調整する想定。
    var framesPerSecond: Double = 8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Assetに実際に入っているコマだけを読み込む。枚数は決め打ちしない。
    private let frames: [UIImage]

    init(level: MascotLevel, framesPerSecond: Double = 8) {
        self.level = level
        self.framesPerSecond = framesPerSecond
        self.frames = level.frameImageNames.compactMap { UIImage(named: $0) }
    }

    var body: some View {
        if frames.isEmpty {
            MascotPlaceholderView(level: level)
        } else if frames.count == 1 || reduceMotion {
            image(frames[0])
        } else {
            // SwiftUIの TimelineView。アプリ内の `TimelineView`（タイムライン画面）と名前が同じなので修飾する。
            SwiftUI.TimelineView(.animation(minimumInterval: 1 / framesPerSecond)) { timeline in
                image(frames[frameIndex(at: timeline.date)])
            }
        }
    }

    private func image(_ uiImage: UIImage) -> some View {
        Image(uiImage: uiImage)
            .resizable()
            .scaledToFit()
            .accessibilityLabel("\(level.title)のイラスト")
    }

    private func frameIndex(at date: Date) -> Int {
        let step = Int((date.timeIntervalSinceReferenceDate * framesPerSecond).rounded(.down))
        let count = frames.count
        return ((step % count) + count) % count
    }
}

#Preview {
    MascotAnimationView(level: .lv2)
        .frame(height: 200)
        .padding()
        .background(.appBackground)
}
