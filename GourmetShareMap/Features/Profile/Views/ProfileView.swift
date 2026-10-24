//
//  ProfileView.swift
//  GourmetShareMap
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @StateObject private var viewModel = ProfileViewModel()
    @State private var isEditingProfile = false

    private let backgroundColor = Color(red: 0.984, green: 0.968, blue: 0.937)
    private let accentOrange = Color(red: 0.76, green: 0.35, blue: 0.22)

    var body: some View {
        // フレンド一覧・フレンド追加へ push で遷移する。
        NavigationStack {
            content
                // ルートは独自のヘッダーを持つため、ナビゲーションバーを出さない。
                .toolbarVisibility(.hidden, for: .navigationBar)
                .navigationDestination(for: FriendRoute.self) { route in
                    switch route {
                    case .list: FriendListView()
                    case .add: FriendAddView()
                    }
                }
        }
    }

    private var content: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    if viewModel.isLoading {
                        loadingView
                    } else if let errorMessage = viewModel.errorMessage {
                        errorView(message: errorMessage)
                    } else {
                        profileSummary

                        statsRow

                        recentRecordsSection

                        friendListButton
                    }

                    logoutButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .task {
            await viewModel.load()
        }
        .sheet(isPresented: $isEditingProfile, onDismiss: {
            // 保存・キャンセルどちらで閉じても再読込する。キャンセル時はDBが変わっていないため、
            // 結果的に表示内容は変わらない。
            Task { await viewModel.load() }
        }) {
            ProfileEditView()
        }
    }

    private var header: some View {
        Text("04 プロフィール")
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(.black)
            .padding(.top, 8)
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

    private var avatarView: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.95, green: 0.80, blue: 0.62), Color(red: 0.89, green: 0.63, blue: 0.45)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 72, height: 72)
            .overlay {
                if let avatarURL = viewModel.avatarURL {
                    AsyncImage(url: avatarURL) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 72, height: 72)
                                .clipShape(Circle())
                        } else {
                            // 読み込み中・失敗時は固定アイコンにフォールバックする。
                            avatarFallbackIcon
                        }
                    }
                } else {
                    avatarFallbackIcon
                }
            }
            .overlay {
                Circle().stroke(Color.white, lineWidth: 3)
            }
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }

    private var avatarFallbackIcon: some View {
        Image(systemName: "person.fill")
            .font(.system(size: 30))
            .foregroundStyle(.white)
    }

    private var profileSummary: some View {
        HStack(spacing: 16) {
            avatarView

            Text(viewModel.displayName)
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(.black)

            Spacer()

            Button {
                isEditingProfile = true
            } label: {
                Label("編集", systemImage: "pencil")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accentOrange)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .overlay {
                        Capsule().stroke(accentOrange, lineWidth: 1.5)
                    }
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            ProfileStatColumn(value: "\(viewModel.storeCount)", label: "登録店舗")

            Divider().frame(height: 36)

            ProfileStatColumn(value: "\(viewModel.maxRepeatCount)回", label: "最大リピート")

            Divider().frame(height: 36)

            ProfileStatColumn(value: "\(viewModel.friendCount)", label: "フレンド")
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

            VStack(spacing: 10) {
                ForEach(viewModel.recentRecords) { record in
                    RecentRecordRow(record: record)
                }
            }
        }
    }

    private var friendListButton: some View {
        NavigationLink(value: FriendRoute.list) {
            Text("フレンド一覧")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(accentOrange)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(accentOrange, lineWidth: 1.5)
                }
        }
    }

    private var logoutButton: some View {
        Button {
            Task { await authViewModel.signOut() }
        } label: {
            Text("ログアウト")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.black.opacity(0.5))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
    }
}

#Preview {
    ProfileView()
        .environmentObject(AuthViewModel())
        .environment(FriendRequestStore())
}
