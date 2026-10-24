//
//  CameraCaptureView.swift
//  GourmetShareMap
//

import AVFoundation
import PhotosUI
import SwiftUI

/// 全画面のカメラ。左下のライブラリボタンから写真を選ぶこともできる。
/// 撮影または選択が終わると `onComplete` に写真を渡して閉じる。
struct CameraCaptureView: View {
    /// ライブラリから一度に選べる枚数。
    var maxSelectionCount = 10
    let onComplete: ([RecordPhoto]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var viewModel = CameraViewModel()
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isProcessing = false
    @State private var isFlashing = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch viewModel.state {
            case .starting, .running:
                CameraPreview(viewModel: viewModel)
                    .ignoresSafeArea()
            case .unavailable:
                unavailableMessage(
                    icon: "camera.badge.ellipsis",
                    text: "この端末ではカメラを利用できません。\n左下のボタンから写真を選択してください。"
                )
            case .denied:
                unavailableMessage(
                    icon: "camera.fill",
                    text: "カメラの利用が許可されていません。\n設定アプリから許可するか、左下のボタンから写真を選択してください。",
                    showsSettingsButton: true
                )
            }

            if isFlashing {
                Color.white.ignoresSafeArea()
            }

            VStack {
                topBar
                Spacer()
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.6), in: Capsule())
                }
                bottomBar
            }
            .padding(.horizontal, 20)

            if isProcessing {
                ProgressView()
                    .tint(.white)
                    .controlSize(.large)
            }
        }
        .statusBarHidden()
        .task { await viewModel.start() }
        .onDisappear { viewModel.stop() }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            pickerItems = []
            Task { await loadLibraryItems(items) }
        }
    }

    // MARK: - Controls

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.4), in: Circle())
            }
            .accessibilityLabel("閉じる")
            Spacer()
        }
        .padding(.top, 8)
    }

    private var bottomBar: some View {
        HStack {
            libraryButton
            Spacer()
            shutterButton
            Spacer()
            switchCameraButton
        }
        .padding(.bottom, 24)
        .disabled(isProcessing)
    }

    private var libraryButton: some View {
        PhotosPicker(
            selection: $pickerItems,
            maxSelectionCount: maxSelectionCount,
            selectionBehavior: .ordered,
            matching: .images,
            // .current にしておくと HEIC などが変換されず、EXIF の位置情報がそのまま残る
            preferredItemEncoding: .current
        ) {
            VStack(spacing: 4) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 22))
                    .frame(width: 56, height: 56)
                    .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.white, lineWidth: 1.5)
                    }
                Text("ライブラリ")
                    .font(.caption2.bold())
            }
            .foregroundStyle(.white)
        }
        .accessibilityLabel("ライブラリから写真を選択")
    }

    private var shutterButton: some View {
        let isEnabled = viewModel.state == .running && !viewModel.isCapturing
        return Button {
            Task { await capture() }
        } label: {
            Circle()
                .fill(.white)
                .frame(width: 68, height: 68)
                .padding(5)
                .overlay(Circle().strokeBorder(.white, lineWidth: 4))
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel("撮影")
    }

    private var switchCameraButton: some View {
        Button {
            Task { await viewModel.switchCamera() }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 22))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(.white.opacity(0.2), in: Circle())
        }
        .disabled(viewModel.state != .running)
        .opacity(viewModel.state == .running ? 1 : 0)
        .accessibilityLabel("カメラを切り替え")
    }

    private func unavailableMessage(icon: String, text: String, showsSettingsButton: Bool = false) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 44))
            Text(text)
                .font(.subheadline)
                .multilineTextAlignment(.center)
            if showsSettingsButton {
                Button("設定を開く") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(.subheadline.bold())
                .foregroundStyle(.appPrimary)
            }
        }
        .foregroundStyle(.white)
        .padding(32)
    }

    // MARK: - Actions

    private func capture() async {
        errorMessage = nil
        isProcessing = true
        defer { isProcessing = false }
        flash()
        do {
            let data = try await viewModel.capture()
            guard let photo = await RecordPhoto.make(from: data) else {
                throw CameraServiceError.captureFailed
            }
            finish(with: [photo])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadLibraryItems(_ items: [PhotosPickerItem]) async {
        errorMessage = nil
        isProcessing = true
        defer { isProcessing = false }
        let photos = await RecordPhoto.load(from: items)
        guard !photos.isEmpty else {
            errorMessage = "写真を読み込めませんでした"
            return
        }
        finish(with: photos)
    }

    private func finish(with photos: [RecordPhoto]) {
        onComplete(photos)
        dismiss()
    }

    /// シャッターを切ったことがわかるよう、一瞬白く光らせる。
    private func flash() {
        isFlashing = true
        withAnimation(.easeOut(duration: 0.25)) { isFlashing = false }
    }
}

/// カメラのプレビュー（AVCaptureVideoPreviewLayer）。
private struct CameraPreview: UIViewRepresentable {
    let viewModel: CameraViewModel

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var onLayout: (() -> Void)?

        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?()
        }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        viewModel.attach(view.previewLayer)
        view.onLayout = { [viewModel] in viewModel.applyPreviewRotation() }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

#Preview {
    CameraCaptureView { _ in }
}
