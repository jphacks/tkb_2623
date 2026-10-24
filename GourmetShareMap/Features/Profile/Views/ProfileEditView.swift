//
//  ProfileEditView.swift
//  GourmetShareMap
//

import PhotosUI
import SwiftUI
import UIKit

struct ProfileEditView: View {
    @StateObject private var viewModel: ProfileEditViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var cropCandidate: CropCandidate?

    /// クロップ画面に渡す画像。UIImageはIdentifiableではないため、.fullScreenCover(item:)用に包む。
    private struct CropCandidate: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    private let backgroundColor = Color(red: 0.984, green: 0.968, blue: 0.937)
    private let accentOrange = Color(red: 0.76, green: 0.35, blue: 0.22)

    // デフォルト引数の評価はnonisolatedなコンテキストで行われ、MainActor隔離の
    // ProfileEditViewModel()を直接呼べないため、init本体でnilの場合に生成する。
    init(viewModel: ProfileEditViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? ProfileEditViewModel())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundColor.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let errorMessage = viewModel.errorMessage {
                            errorBanner(errorMessage)
                        }

                        avatarSection

                        nameField

                        bioField
                    }
                    .padding(20)
                }

                if viewModel.isLoading {
                    ProgressView()
                }
            }
            .navigationTitle("プロフィール編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                        .disabled(viewModel.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Button("保存") {
                            Task { await save() }
                        }
                        .disabled(viewModel.isLoading)
                    }
                }
            }
        }
        .task {
            await viewModel.load()
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task { await loadSelectedPhoto(newItem) }
        }
        .fullScreenCover(item: $cropCandidate) { candidate in
            ProfileImageCropView(
                image: candidate.image,
                onCancel: {
                    // 選択前の状態を維持する。同じ写真を選び直せるようselectedPhotoItemもリセットする。
                    cropCandidate = nil
                    selectedPhotoItem = nil
                },
                onConfirm: { data in
                    viewModel.selectImage(data: data, format: .jpeg)
                    cropCandidate = nil
                    selectedPhotoItem = nil
                }
            )
        }
    }

    private var avatarSection: some View {
        VStack(spacing: 12) {
            ProfileAvatarPreview(previewURL: viewModel.avatarPreviewURL, pendingImageData: viewModel.pendingImageData)

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Text("画像を変更")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accentOrange)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("表示名")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.black.opacity(0.6))
            TextField("表示名を入力", text: $viewModel.name)
                .padding(12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var bioField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("自己紹介")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.black.opacity(0.6))
            TextField("自己紹介を入力", text: $viewModel.bio, axis: .vertical)
                .lineLimit(4...8)
                .padding(12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// 選んだ画像を読み込み、クロップ画面に渡す。実際の反映はクロップ確定後に行う。
    private func loadSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data) else { return }
        cropCandidate = CropCandidate(image: uiImage)
    }

    private func save() async {
        await viewModel.save()
        if viewModel.didSaveSuccessfully {
            dismiss()
        }
    }
}

#Preview {
    ProfileEditView()
}
