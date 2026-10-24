//
//  RecordCreateView.swift
//  GourmetShareMap
//

import SwiftUI

struct RecordCreateView: View {
    /// 登録タブが選ばれているか。選ばれたときに写真がなければカメラを起動する。
    var isActive = true

    @Environment(RecordStore.self) private var recordStore
    @State private var viewModel = RecordCreateViewModel()
    @State private var isCameraPresented = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        PhotoGridEditor(photos: $viewModel.photos)
                        fieldError(.photos)
                    }
                    .id(RecordCreateViewModel.Field.photos)

                    VStack(alignment: .leading, spacing: 8) {
                        candidateHeader
                        StoreCandidatePicker(
                            state: viewModel.searchState,
                            searchedCoordinate: viewModel.searchedCoordinate,
                            selection: $viewModel.selectedCandidate,
                            onRetry: viewModel.retrySearch
                        )
                        fieldError(.store)
                    }
                    .id(RecordCreateViewModel.Field.store)

                    if viewModel.selectedCandidate != nil {
                        categorySection
                            .id(RecordCreateViewModel.Field.category)
                    }

                    section("評価") {
                        StarRatingInput(rating: $viewModel.rating)
                        fieldError(.rating)
                    }
                    .id(RecordCreateViewModel.Field.rating)

                    section("メモ（任意）") {
                        TextField("味や雰囲気などを自由に", text: $viewModel.memo, axis: .vertical)
                            .lineLimit(3...6)
                            .padding(12)
                            .cardBackground(cornerRadius: 12)
                    }

                    saveFooter { firstMissing in
                        withAnimation(.snappy) { proxy.scrollTo(firstMissing, anchor: .top) }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                // 保存中は入力を変更できないようにする。
                .disabled(viewModel.isSaving)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(.appText)
        .background(.appBackground)
        .overlay {
            if let summary = viewModel.savedSummary {
                RecordSavedView(summary: summary) {
                    withAnimation(.snappy) { viewModel.savedSummary = nil }
                    // 「続けて登録する」なので、そのまま次の撮影に進む。
                    isCameraPresented = true
                }
                .transition(.opacity)
            }
        }
        .animation(.snappy, value: viewModel.savedSummary)
        .sensoryFeedback(.success, trigger: viewModel.savedSummary) { _, new in new != nil }
        .sensoryFeedback(.error, trigger: viewModel.showsValidationErrors) { _, new in new }
        .task(id: viewModel.searchKey) {
            await viewModel.search(for: viewModel.searchKey.origin)
        }
        // タブが選ばれたときだけ判定する（onAppear だとカメラを閉じた直後にも呼ばれて開き直す恐れがあるため）。
        .onChange(of: isActive, initial: true) { _, isActive in
            if isActive, viewModel.photos.isEmpty, viewModel.savedSummary == nil {
                isCameraPresented = true
            }
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraCaptureView(maxSelectionCount: RecordCreateViewModel.maxPhotoCount) { photos in
                viewModel.addPhotos(photos)
            }
        }
    }

    /// 保存ボタンを押した後、未入力の項目の下に出すエラー。
    @ViewBuilder
    private func fieldError(_ field: RecordCreateViewModel.Field) -> some View {
        if let message = viewModel.errorMessage(for: field) {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.caption.bold())
                .foregroundStyle(.red)
        }
    }

    // MARK: - Category

    private var categorySection: some View {
        section("カテゴリ") {
            VStack(alignment: .leading, spacing: 6) {
                Picker("カテゴリ", selection: $viewModel.category) {
                    ForEach(RecordCreateViewModel.categories, id: \.self) { category in
                        Text(category).tag(Optional(category))
                    }
                }
                .pickerStyle(.menu)
                .tint(.appText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .cardBackground(cornerRadius: 12)

                fieldError(.category)

                if let shop = viewModel.selectedCandidate,
                   let existing = recordStore.existingRecord(forPlaceID: shop.placeID) {
                    Label("記録済みのお店です。\(existing.repeatNum + 1)回目の訪問として記録を更新します", systemImage: "arrow.trianglehead.2.clockwise")
                        .font(.caption)
                        .foregroundStyle(.appPrimary)
                }
            }
        }
    }

    // MARK: - Save

    @ViewBuilder
    private func saveFooter(scrollToField: @escaping (RecordCreateViewModel.Field) -> Void) -> some View {
        switch viewModel.saveState {
        case let .partiallyFailed(_, failedPhotos):
            VStack(spacing: 12) {
                Label("記録は保存しましたが、\(failedPhotos.count)枚の写真を保存できませんでした", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.appText)
                Button {
                    Task { await viewModel.retryFailedUploads(to: recordStore) }
                } label: {
                    primaryButtonLabel("写真を再送する")
                }
                Button("写真なしで完了する", action: viewModel.discardFailedUploads)
                    .font(.subheadline)
                    .foregroundStyle(.appText.opacity(0.7))
            }
            .padding(16)
            .cardBackground()
        default:
            VStack(spacing: 8) {
                if viewModel.showsValidationErrors, !viewModel.missingFields.isEmpty {
                    Label("未入力の項目があります（メモ以外は必須です）", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.bold())
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if case let .failed(message) = viewModel.saveState {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button {
                    Task {
                        let didStart = await viewModel.save(to: recordStore)
                        if !didStart, let firstMissing = viewModel.missingFields.first {
                            scrollToField(firstMissing)
                        }
                    }
                } label: {
                    primaryButtonLabel("記録を保存")
                }
                .disabled(!viewModel.canSave)
            }
        }
    }

    private func primaryButtonLabel(_ title: String) -> some View {
        ZStack {
            if viewModel.isSaving {
                ProgressView().tint(.white)
            } else {
                Text(title)
            }
        }
        .font(.headline)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(.appPrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var candidateHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            switch viewModel.searchOrigin {
            case nil:
                Label("お店の候補", systemImage: "fork.knife")
            case .currentLocation:
                Label("現在地からの候補", systemImage: "location.fill")
            case .photo(_, _, let takenAt):
                Label("写真の撮影地点からの候補", systemImage: "photo")
                if let takenAt {
                    Text(takenAt.formatted(.dateTime.month().day().hour().minute()) + " 撮影")
                        .font(.caption)
                        .foregroundStyle(.appText.opacity(0.6))
                }
            }
        }
        .font(.subheadline.bold())
        .labelStyle(.titleAndIcon)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.bold())
            content()
        }
    }
}

#Preview {
    RecordCreateView()
        .environment(RecordStore())
}
