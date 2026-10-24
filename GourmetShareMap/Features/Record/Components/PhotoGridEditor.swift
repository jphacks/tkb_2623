//
//  PhotoGridEditor.swift
//  GourmetShareMap
//

import PhotosUI
import SwiftUI

/// 写真の追加・変更・削除・並べ替え・表紙の指定を行うエディタ。
/// 並び順の先頭が表紙になる。
struct PhotoGridEditor: View {
    @Binding var photos: [RecordPhoto]
    var maxCount = 10

    /// 次にカメラ／ライブラリから取得した写真をどう扱うか。
    private enum Target: Equatable {
        case add
        case replace(RecordPhoto.ID)
    }

    @State private var target: Target = .add
    @State private var editingPhotoID: RecordPhoto.ID?
    @State private var draggingPhotoID: RecordPhoto.ID?
    @State private var isCameraPresented = false
    @State private var isLibraryPresented = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let tileSize: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if photos.isEmpty && !isLoading {
                emptyAddCard
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(photos) { photo in
                            photoTile(photo)
                        }
                        if isLoading {
                            ProgressView()
                                .frame(width: tileSize, height: tileSize)
                                .cardBackground(cornerRadius: 12)
                        }
                        if photos.count < maxCount {
                            addTile
                        }
                    }
                    // 削除ボタンがタイルの外にはみ出す分の余白
                    .padding(.top, 6)
                    .padding(.trailing, 6)
                }
                .scrollIndicators(.hidden)

                Text(photos.count > 1 ? "タップで変更・長押しでドラッグして並べ替え" : "写真をタップして変更")
                    .font(.caption)
                    .foregroundStyle(.appText.opacity(0.6))
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraCaptureView(maxSelectionCount: target == .add ? max(maxCount - photos.count, 1) : 1) { captured in
                captured.forEach(apply)
            }
        }
        .photosPicker(
            isPresented: $isLibraryPresented,
            selection: $pickerItems,
            maxSelectionCount: target == .add ? max(maxCount - photos.count, 1) : 1,
            selectionBehavior: .ordered,
            matching: .images,
            // .current にしておくと HEIC などが変換されず、EXIF の位置情報がそのまま残る
            preferredItemEncoding: .current
        )
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            pickerItems = []
            Task { await loadLibraryItems(items) }
        }
    }

    // MARK: - Tiles

    private func photoTile(_ photo: RecordPhoto) -> some View {
        let isCover = photos.first?.id == photo.id
        let isEditing = Binding(
            get: { editingPhotoID == photo.id },
            set: { if !$0 { editingPhotoID = nil } }
        )

        return Image(uiImage: photo.image)
            .resizable()
            .scaledToFill()
            .frame(width: tileSize, height: tileSize)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if isCover {
                    Text("表紙")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.appPrimary, in: Capsule())
                        .padding(5)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if photo.location != nil {
                    Image(systemName: "location.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.black.opacity(0.45), in: Circle())
                        .padding(5)
                        .accessibilityLabel("位置情報あり")
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(draggingPhotoID == photo.id ? AnyShapeStyle(.appPrimary) : AnyShapeStyle(.clear), lineWidth: 2)
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    remove(photo.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(.appText, in: Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                }
                .offset(x: 6, y: -6)
                .accessibilityLabel("写真を削除")
            }
            .contentShape(Rectangle())
            .onTapGesture { editingPhotoID = photo.id }
            .confirmationDialog("写真を編集", isPresented: isEditing, titleVisibility: .hidden) {
                PhotoSourceMenuItems(
                    onSelectCamera: { present(.camera, for: .replace(photo.id)) },
                    onSelectLibrary: { present(.library, for: .replace(photo.id)) }
                )
                if !isCover {
                    Button("表紙にする") { setCover(photo.id) }
                }
                Button("削除", role: .destructive) { remove(photo.id) }
            }
            .draggable(photo.id.uuidString) {
                Image(uiImage: photo.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: tileSize, height: tileSize)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .dropDestination(for: String.self) { ids, _ in
                guard let id = ids.first.flatMap(UUID.init(uuidString:)) else { return false }
                withAnimation(.snappy) { move(id, to: photo.id) }
                return true
            } isTargeted: { isTargeted in
                if isTargeted { draggingPhotoID = photo.id } else if draggingPhotoID == photo.id { draggingPhotoID = nil }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(isCover ? "表紙の写真" : "写真")
    }

    /// 写真が 0 枚のときに出す、画面幅いっぱいの追加ボタン。
    private var emptyAddCard: some View {
        PhotoSourceMenu(
            onSelectCamera: { present(.camera, for: .add) },
            onSelectLibrary: { present(.library, for: .add) }
        ) {
            VStack(spacing: 12) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(.appPrimary, in: Circle())

                VStack(spacing: 4) {
                    Text("写真を追加")
                        .font(.title3.bold())
                        .foregroundStyle(.appPrimary)
                    Text("お店で撮った写真から、お店の候補を探します")
                        .font(.caption)
                        .foregroundStyle(.appText.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 200)
            .background(.appPrimary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.appPrimary, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .accessibilityLabel("写真を追加")
    }

    private var addTile: some View {
        PhotoSourceMenu(
            onSelectCamera: { present(.camera, for: .add) },
            onSelectLibrary: { present(.library, for: .add) }
        ) {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .semibold))
                Text("追加")
                    .font(.caption.bold())
            }
            .foregroundStyle(.appPrimary)
            .frame(width: tileSize, height: tileSize)
            .background(.appPrimary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.appPrimary, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
        }
        .accessibilityLabel("写真を追加")
    }

    // MARK: - Actions

    private enum Source { case camera, library }

    private func present(_ source: Source, for target: Target) {
        self.target = target
        errorMessage = nil
        switch source {
        case .camera: isCameraPresented = true
        case .library: isLibraryPresented = true
        }
    }

    private func loadLibraryItems(_ items: [PhotosPickerItem]) async {
        isLoading = true
        defer { isLoading = false }

        let loaded = await RecordPhoto.load(from: items)
        if loaded.count < items.count {
            errorMessage = "一部の写真を読み込めませんでした"
        }
        for photo in loaded {
            apply(photo)
        }
    }

    /// 取得した写真を target に応じて追加または差し替える。
    private func apply(_ photo: RecordPhoto) {
        withAnimation(.snappy) {
            if case .replace(let id) = target, let index = photos.firstIndex(where: { $0.id == id }) {
                photos[index] = photo
                // 複数枚が返ってきても差し替えは 1 枚だけ。残りは追加扱いにする。
                target = .add
            } else if photos.count < maxCount {
                photos.append(photo)
            }
        }
    }

    private func remove(_ id: RecordPhoto.ID) {
        withAnimation(.snappy) {
            photos.removeAll { $0.id == id }
        }
    }

    private func setCover(_ id: RecordPhoto.ID) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.snappy) {
            photos.move(fromOffsets: IndexSet(integer: index), toOffset: 0)
        }
    }

    private func move(_ id: RecordPhoto.ID, to destinationID: RecordPhoto.ID) {
        draggingPhotoID = nil
        guard
            id != destinationID,
            let from = photos.firstIndex(where: { $0.id == id }),
            let to = photos.firstIndex(where: { $0.id == destinationID })
        else { return }
        photos.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }
}

#Preview {
    @Previewable @State var photos: [RecordPhoto] = []
    PhotoGridEditor(photos: $photos)
        .padding()
        .background(.appBackground)
}
