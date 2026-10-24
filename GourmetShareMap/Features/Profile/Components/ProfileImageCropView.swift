//
//  ProfileImageCropView.swift
//  GourmetShareMap
//

import SwiftUI

/// PhotosPickerで選んだ画像を、円形のクロップガイド内でピンチズーム・ドラッグして
/// 位置・拡大縮小を調整するための画面。SwiftUI標準にクロップUIが無いため、
/// DragGesture/MagnificationGestureを使って自前実装している。
///
/// OKで確定すると、ガイド内に表示されている範囲だけを正方形に切り出し、
/// アバター表示・Storage容量に対して過大にならない解像度にリサイズしたJPEGデータを返す。
/// キャンセルした場合は何も呼ばれず、呼び出し元は選択前の状態を維持する。
struct ProfileImageCropView: View {
    let image: UIImage
    let onCancel: () -> Void
    let onConfirm: (Data) -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    /// クロップガイド（円）の直径。ポイント単位。
    private let viewportSize: CGFloat = 280
    private let minUserScale: CGFloat = 1
    private let maxUserScale: CGFloat = 4
    /// 書き出す正方形画像の一辺（ピクセル）。アバター表示（最大100pt前後）に対して
    /// Retina表示でも十分な解像度を確保しつつ、過大なファイルサイズにならない値。
    private let outputPixelSize: CGFloat = 512
    private let jpegQuality: CGFloat = 0.85

    /// ガイドいっぱいに画像が常に覆うよう、画像をどの倍率で表示し始めるか（aspect fill相当）。
    private var baseScale: CGFloat {
        guard image.size.width > 0, image.size.height > 0 else { return 1 }
        return max(viewportSize / image.size.width, viewportSize / image.size.height)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                Image(uiImage: image)
                    .resizable()
                    .frame(
                        width: image.size.width * baseScale * scale,
                        height: image.size.height * baseScale * scale
                    )
                    .offset(offset)

                dimmedOverlay
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(SimultaneousGesture(dragGesture, magnificationGesture))
            .navigationTitle("画像を調整")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { confirmCrop() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var dimmedOverlay: some View {
        Rectangle()
            .fill(Color.black.opacity(0.6))
            .reverseMask {
                Circle().frame(width: viewportSize, height: viewportSize)
            }
            .overlay {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 2)
                    .frame(width: viewportSize, height: viewportSize)
            }
            .allowsHitTesting(false)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                clampOffset()
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(lastScale * value, minUserScale), maxUserScale)
                clampOffset()
            }
            .onEnded { _ in
                lastScale = scale
            }
    }

    /// 画像がガイドの外にはみ出して空白ができないよう、オフセットの取りうる範囲を制限する。
    private func clampOffset() {
        let displayedWidth = image.size.width * baseScale * scale
        let displayedHeight = image.size.height * baseScale * scale
        let maxX = max(0, (displayedWidth - viewportSize) / 2)
        let maxY = max(0, (displayedHeight - viewportSize) / 2)
        offset.width = min(max(offset.width, -maxX), maxX)
        offset.height = min(max(offset.height, -maxY), maxY)
    }

    /// 現在の表示倍率・オフセットから、ガイド内に見えている範囲を元画像の座標系に逆算し、
    /// その範囲だけを正方形に描き直してリサイズする。
    private func confirmCrop() {
        let totalScale = baseScale * scale
        guard totalScale > 0 else {
            onCancel()
            return
        }
        let displayedSize = CGSize(
            width: image.size.width * totalScale,
            height: image.size.height * totalScale
        )
        let cropOrigin = CGPoint(
            x: (displayedSize.width / 2 - viewportSize / 2 - offset.width) / totalScale,
            y: (displayedSize.height / 2 - viewportSize / 2 - offset.height) / totalScale
        )
        let cropSide = viewportSize / totalScale
        let cropRect = CGRect(x: cropOrigin.x, y: cropOrigin.y, width: cropSide, height: cropSide)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1 // outputPixelSizeをそのままピクセル数として扱う。
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: outputPixelSize, height: outputPixelSize), format: format
        )
        let croppedImage = renderer.image { _ in
            let drawScale = outputPixelSize / cropRect.width
            image.draw(in: CGRect(
                x: -cropRect.minX * drawScale,
                y: -cropRect.minY * drawScale,
                width: image.size.width * drawScale,
                height: image.size.height * drawScale
            ))
        }

        guard let data = croppedImage.jpegData(compressionQuality: jpegQuality) else {
            onCancel()
            return
        }
        onConfirm(data)
    }
}

private extension View {
    /// 指定したshapeの内側だけを透過させる「反転マスク」。
    /// 円形のクロップガイド外を暗転させるために使う（SwiftUIコミュニティで知られた定番の実装）。
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            Rectangle()
                .overlay {
                    mask().blendMode(.destinationOut)
                }
                .compositingGroup()
        }
    }
}

#Preview {
    ProfileImageCropView(
        image: UIImage(systemName: "photo.fill") ?? UIImage(),
        onCancel: {},
        onConfirm: { _ in }
    )
}
