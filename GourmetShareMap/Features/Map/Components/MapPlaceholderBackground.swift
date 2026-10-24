//
//  MapPlaceholderBackground.swift
//  GourmetShareMap

import SwiftUI

/// Google Maps SDK導入までの仮の地図背景。
/// TODO: Google Maps SDK (GMSMapView) 導入後、このViewをGoogleMap本体に置き換える。
struct MapPlaceholderBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.90, green: 0.93, blue: 0.87)

            Canvas { context, size in
                let roadColor = Color.white.opacity(0.9)
                let verticalLines = stride(from: 0.1, through: 0.9, by: 0.2)
                for ratio in verticalLines {
                    var path = Path()
                    path.move(to: CGPoint(x: size.width * ratio, y: 0))
                    path.addLine(to: CGPoint(x: size.width * ratio, y: size.height))
                    context.stroke(path, with: .color(roadColor), lineWidth: 3)
                }

                let horizontalLines = stride(from: 0.15, through: 0.95, by: 0.22)
                for ratio in horizontalLines {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: size.height * ratio))
                    path.addLine(to: CGPoint(x: size.width, y: size.height * ratio))
                    context.stroke(path, with: .color(roadColor), lineWidth: 3)
                }
            }

            Circle()
                .fill(Color(red: 0.75, green: 0.85, blue: 0.72))
                .frame(width: 140, height: 140)
                .offset(x: 110, y: -90)
                .blur(radius: 2)
        }
    }
}

#Preview {
    MapPlaceholderBackground()
        .frame(height: 400)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
}
