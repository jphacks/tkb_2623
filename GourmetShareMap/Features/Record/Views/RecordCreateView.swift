//
//  RecordCreateView.swift
//  GourmetShareMap
//

import SwiftUI

struct RecordCreateView: View {
    @Environment(RecordStore.self) private var recordStore
    @State private var viewModel = RecordCreateViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("03 店舗登録")
                    .font(.system(size: 20, weight: .bold))
                    .padding(.top, 8)

                PhotoGridEditor(photos: $viewModel.photos)

                VStack(alignment: .leading, spacing: 8) {
                    candidateHeader
                    StoreCandidatePicker(
                        state: viewModel.searchState,
                        searchedCoordinate: viewModel.searchedCoordinate,
                        selection: $viewModel.selectedCandidate,
                        onRetry: viewModel.retrySearch
                    )
                }

                if viewModel.selectedCandidate != nil {
                    categorySection
                }

                section("評価") {
                    StarRatingInput(rating: $viewModel.rating)
                }

                section("メモ") {
                    TextField("味や雰囲気などを自由に", text: $viewModel.memo, axis: .vertical)
                        .lineLimit(3...6)
                        .padding(12)
                        .cardBackground(cornerRadius: 12)
                }

                saveFooter
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            // 保存中は入力を変更できないようにする。
            .disabled(viewModel.isSaving)
        }
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(.appText)
        .background(.appBackground)
        .overlay(alignment: .top) {
            if let message = viewModel.savedMessage {
                savedBanner(message)
            }
        }
        .sensoryFeedback(.success, trigger: viewModel.savedMessage) { _, new in new != nil }
        .task(id: viewModel.searchKey) {
            await viewModel.search(for: viewModel.searchKey.origin)
        }
        .task(id: viewModel.savedMessage) {
            guard viewModel.savedMessage != nil else { return }
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(.snappy) { viewModel.savedMessage = nil }
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
    private var saveFooter: some View {
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
                if case let .failed(message) = viewModel.saveState {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button {
                    Task { await viewModel.save(to: recordStore) }
                } label: {
                    primaryButtonLabel("記録を保存")
                }
                .disabled(!viewModel.canSave)
                .opacity(viewModel.canSave || viewModel.isSaving ? 1 : 0.4)
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

    private func savedBanner(_ message: String) -> some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.appPrimary, in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
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
