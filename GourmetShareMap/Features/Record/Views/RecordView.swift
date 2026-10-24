//
//  RecordView.swift
//  GourmetShareMap
//

import SwiftUI

struct RecordView: View {
    @State private var viewModel = RecordViewModel()

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

                section("評価") {
                    StarRatingInput(rating: $viewModel.rating)
                }

                section("メモ") {
                    TextField("味や雰囲気などを自由に", text: $viewModel.memo, axis: .vertical)
                        .lineLimit(3...6)
                        .padding(12)
                        .cardBackground(cornerRadius: 12)
                }

                Button(action: viewModel.save) {
                    Text("記録を保存")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(.appPrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(!viewModel.canSave)
                .opacity(viewModel.canSave ? 1 : 0.4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(.appText)
        .background(.appBackground)
        .task(id: viewModel.searchKey) {
            await viewModel.search(for: viewModel.searchKey.origin)
        }
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
    RecordView()
}
