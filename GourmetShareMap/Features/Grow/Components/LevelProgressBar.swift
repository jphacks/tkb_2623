//
//  LevelProgressBar.swift
//  GourmetShareMap
//

import SwiftUI

/// 現在のレベルと、次のレベルまでの残り件数を出すバー。最大レベルでは満タンになる。
struct LevelProgressBar: View {
    let progress: MascotProgress

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(progress.level.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.appText)

                Spacer(minLength: 0)

                Text(progress.progressText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.appText.opacity(0.6))
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.85))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: 0xE09A4B), .appPrimary],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        // 0件でも帯が見えるように最小幅を持たせる。
                        .frame(width: max(10, geometry.size.width * progress.fraction))
                }
            }
            .frame(height: 9)
        }
        .animation(.easeOut(duration: 0.35), value: progress.fraction)
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(progress.level.title)、\(progress.progressText)")
    }
}

#Preview {
    VStack(spacing: 24) {
        LevelProgressBar(progress: MascotProgress(storeCount: 2))
        LevelProgressBar(progress: MascotProgress(storeCount: 12))
        LevelProgressBar(progress: MascotProgress(storeCount: 24))
    }
    .padding()
    .background(.appBackground)
}
