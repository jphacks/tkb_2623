//
//  ProfileEditView.swift
//  GourmetShareMap
//

import PhotosUI
import SwiftUI

struct ProfileEditView: View {
    @StateObject private var viewModel: ProfileEditViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhotoItem: PhotosPickerItem?

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

    private func loadSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        viewModel.selectImage(data: data, format: imageFormat(for: data))
    }

    /// PNGの先頭バイト列を見て、PNG/JPEGどちらでアップロードするかを判定する。
    /// 判定できない場合はJPEGとして扱う。
    private func imageFormat(for data: Data) -> RecordImageFormat {
        let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        return data.starts(with: pngSignature) ? .png : .jpeg
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
