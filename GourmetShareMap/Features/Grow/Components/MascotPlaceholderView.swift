//
//  MascotPlaceholderView.swift
//  GourmetShareMap
//

import SwiftUI

/// キャラクター画像がAssetに見つからないときの仮描き。レベルごとに装備と動きが変わる。
/// Lv.1 装備なし・少し小さい / Lv.2 手ぬぐい＋湯気 / Lv.3 コック帽＋きらめき。
// NOTE: 各キャラの `{character}_01`〜`08` がAssetに入っていれば通常はこのViewは使われない（画像読み込み失敗時の保険）。
struct MascotPlaceholderView: View {
    let level: MascotLevel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 描画の基準サイズ。この座標系で描いて、表示サイズに合わせて拡縮する。
    private static let designSize = CGSize(width: 100, height: 92)

    private let bowlLine = Color(hex: 0xD9CDB7)
    private let rice = Color(hex: 0xF6F1E6)
    private let steamColor = Color(hex: 0xC9A86F)
    private let sparkleColor = Color(hex: 0xE9B44C)
    private let hatColor = Color(hex: 0xFFFDF8)
    private let hatBand = Color(hex: 0xF3EADA)
    private let hatLine = Color(hex: 0xDCCFB4)

    var body: some View {
        Group {
            if reduceMotion {
                Canvas { context, size in draw(in: &context, size: size, time: 0) }
            } else {
                // SwiftUIの TimelineView。アプリ内の `TimelineView`（タイムライン画面）と名前が同じなので修飾する。
                SwiftUI.TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        draw(in: &context, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
                    }
                }
            }
        }
        .accessibilityLabel("\(level.title)のイラスト")
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        // Lv.1 はまだ小さい。
        let levelScale = level == .lv1 ? 0.86 : 1.0
        let unit = min(size.width / Self.designSize.width, size.height / Self.designSize.height) * levelScale
        guard unit > 0 else { return }

        // 呼吸するような上下動。
        let bob = reduceMotion ? 0 : sin(time * 1.7) * 2.2
        context.translateBy(
            x: (size.width - Self.designSize.width * unit) / 2,
            y: (size.height - Self.designSize.height * unit) / 2 + bob * unit
        )
        context.scaleBy(x: unit, y: unit)

        if level == .lv2 { drawSteam(in: &context, time: time) }
        drawBowl(in: &context)
        drawFace(in: &context)
        switch level {
        case .lv1: break
        case .lv2: drawHeadband(in: &context)
        case .lv3: drawChefHat(in: &context)
        }
        if level == .lv3 { drawSparkles(in: &context, time: time) }
    }

    private func drawBowl(in context: inout GraphicsContext) {
        var bowl = Path()
        bowl.move(to: CGPoint(x: 22, y: 48))
        bowl.addQuadCurve(to: CGPoint(x: 78, y: 48), control: CGPoint(x: 50, y: 104))
        bowl.closeSubpath()
        context.fill(bowl, with: .color(.appCard))
        context.stroke(bowl, with: .color(bowlLine), lineWidth: 2)

        let rim = Path(ellipseIn: CGRect(x: 22, y: 42, width: 56, height: 12))
        context.fill(rim, with: .color(rice))
        context.stroke(rim, with: .color(bowlLine), lineWidth: 1.8)
    }

    private func drawFace(in context: inout GraphicsContext) {
        for x in [41.0, 59.0] {
            let eye = Path(ellipseIn: CGRect(x: x - 2.6, y: 55, width: 5.2, height: 5.2))
            context.fill(eye, with: .color(.appText))
        }
        var smile = Path()
        smile.move(to: CGPoint(x: 45, y: 65))
        smile.addQuadCurve(to: CGPoint(x: 55, y: 65), control: CGPoint(x: 50, y: 71))
        context.stroke(smile, with: .color(.appText), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
    }

    /// Lv.2 の手ぬぐい。茶碗のふちに巻きつけて、右側に結び目を出す。
    private func drawHeadband(in context: inout GraphicsContext) {
        var band = Path()
        band.move(to: CGPoint(x: 23, y: 45))
        band.addQuadCurve(to: CGPoint(x: 77, y: 45), control: CGPoint(x: 50, y: 25))
        band.addQuadCurve(to: CGPoint(x: 23, y: 45), control: CGPoint(x: 50, y: 37))
        band.closeSubpath()
        context.fill(band, with: .color(.appPrimary))

        var knot = Path()
        knot.move(to: CGPoint(x: 75, y: 41))
        knot.addLine(to: CGPoint(x: 88, y: 35))
        knot.addLine(to: CGPoint(x: 84, y: 48))
        knot.closeSubpath()
        context.fill(knot, with: .color(.appPrimary))
    }

    /// Lv.3 のコック帽。ふくらみ3つと土台を同じ色で塗り重ねて、ひとつの輪郭に見せる。
    private func drawChefHat(in context: inout GraphicsContext) {
        var puffs = Path()
        puffs.addEllipse(in: CGRect(x: 26, y: 21, width: 21, height: 21))
        puffs.addEllipse(in: CGRect(x: 39, y: 14, width: 23, height: 23))
        puffs.addEllipse(in: CGRect(x: 53, y: 21, width: 21, height: 21))
        puffs.addRoundedRect(in: CGRect(x: 29, y: 30, width: 42, height: 14), cornerSize: CGSize(width: 5, height: 5))
        context.fill(puffs, with: .color(hatColor))

        let brim = Path(roundedRect: CGRect(x: 28, y: 33, width: 44, height: 12), cornerSize: CGSize(width: 5, height: 5))
        context.fill(brim, with: .color(hatBand))
        context.stroke(brim, with: .color(hatLine), lineWidth: 1.6)
    }

    private func drawSteam(in context: inout GraphicsContext, time: TimeInterval) {
        for (index, x) in [38.0, 50.0, 62.0].enumerated() {
            let phase = ((time / 3.2) + Double(index) * 0.33).truncatingRemainder(dividingBy: 1)
            let rise = phase * 16
            let opacity = sin(phase * .pi) * 0.7

            var path = Path()
            path.move(to: CGPoint(x: x, y: 36 - rise))
            path.addQuadCurve(to: CGPoint(x: x, y: 28 - rise), control: CGPoint(x: x + 6, y: 32 - rise))
            path.addQuadCurve(to: CGPoint(x: x, y: 20 - rise), control: CGPoint(x: x - 6, y: 24 - rise))
            context.stroke(
                path,
                with: .color(steamColor.opacity(opacity)),
                style: StrokeStyle(lineWidth: 2.6, lineCap: .round)
            )
        }
    }

    private func drawSparkles(in context: inout GraphicsContext, time: TimeInterval) {
        let points = [CGPoint(x: 15, y: 42), CGPoint(x: 86, y: 26), CGPoint(x: 83, y: 58)]
        for (index, point) in points.enumerated() {
            let phase = ((time / 2.4) + Double(index) * 0.33).truncatingRemainder(dividingBy: 1)
            let wave = sin(phase * .pi)
            let radius = 1.6 + wave * 2.2
            let circle = Path(ellipseIn: CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            context.fill(circle, with: .color(sparkleColor.opacity(0.3 + wave * 0.6)))
        }
    }
}

#Preview {
    HStack(spacing: 0) {
        ForEach(MascotLevel.allCases) { level in
            VStack {
                MascotPlaceholderView(level: level)
                    .frame(height: 140)
                Text(level.title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.appText)
            }
        }
    }
    .padding()
    .background(.appBackground)
}
