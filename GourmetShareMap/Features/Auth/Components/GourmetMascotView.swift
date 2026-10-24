//
//  GourmetMascotView.swift
//  GourmetShareMap
//

import SwiftUI

/// ご飯茶碗のキャラクターと地図ピンのイラスト。本物のアートワークがアセットに追加されたら
/// このView自体をImage(.loginMascot)などに差し替えればよい。
struct GourmetMascotView: View {
    private let pinColor = Color(red: 0.78, green: 0.35, blue: 0.22)
    private let treeColor = Color(red: 0.45, green: 0.64, blue: 0.42)
    private let trunkColor = Color(red: 0.56, green: 0.43, blue: 0.31)
    private let roofColor = Color(red: 0.70, green: 0.32, blue: 0.23)
    private let wallColor = Color(red: 0.93, green: 0.86, blue: 0.72)

    private let treePositions: [CGPoint] = [
        CGPoint(x: 32, y: 62), CGPoint(x: 54, y: 38), CGPoint(x: 196, y: 44),
        CGPoint(x: 206, y: 142), CGPoint(x: 172, y: 186), CGPoint(x: 24, y: 128),
        CGPoint(x: 70, y: 196),
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.91, green: 0.95, blue: 0.88), Color(red: 0.80, green: 0.90, blue: 0.81)],
                startPoint: .top,
                endPoint: .bottom
            )

            windingPath

            pond

            ForEach(Array(treePositions.enumerated()), id: \.offset) { _, point in
                TreeShape(treeColor: treeColor, trunkColor: trunkColor)
                    .position(point)
            }

            PagodaShape(roofColor: roofColor, wallColor: wallColor)
                .position(x: 180, y: 52)

            BowlCharacterView()
                .frame(width: 128, height: 100)
                .position(x: 112, y: 148)

            MapPinShape()
                .fill(pinColor)
                .frame(width: 54, height: 70)
                .position(x: 112, y: 62)

            Circle()
                .fill(Color.white)
                .frame(width: 16, height: 16)
                .position(x: 112, y: 50)
        }
        .frame(width: 220, height: 220)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white, lineWidth: 5))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 6)
    }

    private var windingPath: some View {
        Path { path in
            path.move(to: CGPoint(x: -10, y: 150))
            path.addCurve(
                to: CGPoint(x: 230, y: 95),
                control1: CGPoint(x: 80, y: 195),
                control2: CGPoint(x: 150, y: 55)
            )
        }
        .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 12, lineCap: .round))
    }

    private var pond: some View {
        Ellipse()
            .fill(Color(red: 0.74, green: 0.86, blue: 0.90))
            .frame(width: 54, height: 28)
            .position(x: 38, y: 172)
    }
}

private struct TreeShape: View {
    let treeColor: Color
    let trunkColor: Color

    var body: some View {
        VStack(spacing: -2) {
            Circle()
                .fill(treeColor)
                .frame(width: 22, height: 22)
            Rectangle()
                .fill(trunkColor)
                .frame(width: 4, height: 7)
        }
    }
}

private struct PagodaShape: View {
    let roofColor: Color
    let wallColor: Color

    var body: some View {
        VStack(spacing: 0) {
            Triangle().fill(roofColor).frame(width: 36, height: 12)
            Rectangle().fill(wallColor).frame(width: 24, height: 8)
            Triangle().fill(roofColor).frame(width: 28, height: 10)
            Rectangle().fill(wallColor).frame(width: 16, height: 12)
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct MapPinShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = rect.width / 2
        let center = CGPoint(x: rect.midX, y: rect.minY + radius)
        path.addArc(center: center, radius: radius, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
        path.move(to: CGPoint(x: rect.midX - radius * 0.82, y: center.y + radius * 0.5))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX + radius * 0.82, y: center.y + radius * 0.5))
        path.closeSubpath()
        return path
    }
}

private struct BowlCharacterView: View {
    var body: some View {
        ZStack {
            BowlShape()
                .fill(Color.white)
                .overlay(BowlShape().stroke(Color(red: 0.85, green: 0.80, blue: 0.70), lineWidth: 2))

            Ellipse()
                .fill(Color(red: 0.95, green: 0.92, blue: 0.86))
                .frame(width: 118, height: 14)
                .offset(y: -6)

            HStack(spacing: 26) {
                Circle().fill(Color.black).frame(width: 7, height: 7)
                Circle().fill(Color.black).frame(width: 7, height: 7)
            }
            .offset(y: 4)

            SmileShape()
                .stroke(Color.black, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 26, height: 12)
                .offset(y: 18)
        }
    }
}

private struct BowlShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY + 14)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.minY - 18)
        )
        return path
    }
}

private struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY)
        )
        return path
    }
}

#Preview {
    GourmetMascotView()
        .padding()
}
