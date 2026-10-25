//
//  FriendProfileView.swift
//  GourmetShareMap
//

import SwiftUI

/// タイムラインの投稿カードから開く、フレンドのプロフィール画面（シート表示）。
/// 自分の`ProfileView`と違い、編集・ログアウト・フレンド一覧など自分専用のUIは持たない。
struct FriendProfileView: View {
    @StateObject private var viewModel: ProfileViewModel
    @Environment(\.dismiss) private var dismiss

    private let backgroundColor = Color(red: 0.984, green: 0.968, blue: 0.937)
    private let accentOrange = Color(red: 0.76, green: 0.35, blue: 0.22)

    init(userID: UUID) {
        _viewModel = StateObject(wrappedValue: ProfileViewModel(target: .friend(userID: userID)))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundColor.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if viewModel.isLoading {
                            loadingView
                        } else if let errorMessage = viewModel.errorMessage {
                            // フォロー関係のない相手を指定した場合もここに来る（0件がPostgrestErrorになるため）。
                            errorView(message: errorMessage)
                        } else {
                            profileSummary

                            if let bio = viewModel.bio?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty {
                                bioText(bio)
                            }

                            statsRow

                            recentRecordsSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("プロフィール")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .task {
            await viewModel.load()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("読み込み中…")
                .font(.system(size: 14))
                .foregroundStyle(.black.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(accentOrange)
            Text("読み込みに失敗しました")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.black)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.black.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var profileSummary: some View {
        HStack(spacing: 16) {
            ProfileAvatarPreview(previewURL: viewModel.avatarURL, pendingImageData: nil, size: 72)

            Text(viewModel.displayName.isEmpty ? "名前未設定" : viewModel.displayName)
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(.black)

            Spacer()
        }
    }

    private func bioText(_ bio: String) -> some View {
        Text(bio)
            .font(.system(size: 14))
            .foregroundStyle(.black.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
    }

    // フレンド機能は別タスクで実装中のため、ProfileViewと違いフレンド数の列は出さない
    // （ProfileViewModel.friendCountは常に0で、友達本人の値ではないため）。
    private var statsRow: some View {
        HStack(spacing: 0) {
            ProfileStatColumn(value: "\(viewModel.storeCount)", label: "登録店舗")

            Divider().frame(height: 36)

            ProfileStatColumn(value: "\(viewModel.maxRepeatCount)回", label: "最大リピート")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var recentRecordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近の記録")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.black)

            if viewModel.recentRecords.isEmpty {
                Text("まだ記録がありません")
                    .font(.system(size: 13))
                    .foregroundStyle(.black.opacity(0.5))
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.recentRecords) { record in
                        RecentRecordRow(record: record)
                    }
                }
            }
        }
    }
}

#Preview {
    FriendProfileView(userID: UUID())
}
