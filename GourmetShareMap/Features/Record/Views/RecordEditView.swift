//
//  RecordEditView.swift
//  GourmetShareMap
//

import SwiftUI

/// 登録済みの店舗記録を編集する。座標と写真はこの画面では変更しない。
struct RecordEditView: View {
    @State private var viewModel: RecordEditViewModel
    @Environment(\.dismiss) private var dismiss

    /// 保存が成功したときに呼ばれる。呼び出し側で一覧を読み直す。
    private let onSaved: () -> Void

    init(store: MapStore, onSaved: @escaping () -> Void) {
        _viewModel = State(initialValue: RecordEditViewModel(store: store))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("店舗") {
                    TextField("店舗名", text: $viewModel.name)

                    Picker("カテゴリ", selection: $viewModel.category) {
                        ForEach(PlaceCategoryClassifier.categoryNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                }

                Section("評価") {
                    Picker("評価", selection: $viewModel.rating) {
                        Text("未評価").tag(Int?.none)
                        ForEach(1...5, id: \.self) { value in
                            Text(String(repeating: "★", count: value)).tag(Int?.some(value))
                        }
                    }
                    Stepper("リピート\(viewModel.repeatCount)回", value: $viewModel.repeatCount, in: 1...99)
                }

                Section("メモ") {
                    TextField("メモ", text: $viewModel.memo, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("記録を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            if await viewModel.save() {
                                onSaved()
                                dismiss()
                            }
                        }
                    }
                    .disabled(!viewModel.canSave)
                }
            }
            .disabled(viewModel.isSaving)
            .overlay {
                if viewModel.isSaving {
                    ProgressView()
                }
            }
        }
    }
}

#Preview {
    RecordEditView(
        store: MapStore(
            id: UUID(),
            name: "焼肉 本郷",
            category: "焼肉・肉料理",
            rating: 3.5,
            repeatCount: 2,
            memo: "昼のランチが狙い目。",
            googlePlaceID: nil,
            latitude: 35.7150,
            longitude: 139.7605,
            isMine: true,
            sharedWithFriend: false
        ),
        onSaved: {}
    )
}
