//
//  FriendAddView.swift
//  GourmetShareMap
//

import SwiftUI
import UIKit

/// フレンド追加。自分の user_name を表示し、相手の user_name（完全一致）で検索して申請する。
struct FriendAddView: View {
    @Environment(FriendRequestStore.self) private var requestStore
    @State private var viewModel = FriendAddViewModel()
    @State private var didCopyUserName = false
    @FocusState private var isQueryFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                myUserNameSection
                searchSection
                resultSection
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(.appBackground)
        .navigationTitle("フレンド追加")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadMyUserName() }
    }

    // MARK: - 自分のユーザー名

    private var myUserNameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("あなたのユーザー名")

            HStack(spacing: 12) {
                Text(viewModel.myUserName.map { "@\($0)" } ?? "—")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.appText)
                    .textSelection(.enabled)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let myUserName = viewModel.myUserName {
                    Button {
                        UIPasteboard.general.string = myUserName
                        didCopyUserName = true
                    } label: {
                        Label(didCopyUserName ? "コピーしました" : "コピー",
                              systemImage: didCopyUserName ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.appPrimary)
                }
            }
            .padding(16)
            .background(.appCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text("このユーザー名を友だちに伝えると、検索して申請してもらえます。")
                .font(.system(size: 12))
                .foregroundStyle(.appText.opacity(0.6))
        }
        .task(id: didCopyUserName) {
            // 「コピーしました」の表示を少しして元に戻す。
            guard didCopyUserName else { return }
            try? await Task.sleep(for: .seconds(2))
            didCopyUserName = false
        }
    }

    // MARK: - 検索

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("ユーザー名で探す")

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text("@")
                        .foregroundStyle(.appText.opacity(0.4))
                    TextField("ユーザー名を入力", text: $viewModel.query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .submitLabel(.search)
                        .focused($isQueryFocused)
                        .onSubmit { Task { await search() } }
                }
                .padding(12)
                .background(.appCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button {
                    Task { await search() }
                } label: {
                    Text("検索")
                        .font(.system(size: 15, weight: .bold))
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.appPrimary)
                .disabled(!viewModel.canSearch)
            }

            Text("ユーザー名が完全に一致する人だけが表示されます。")
                .font(.system(size: 12))
                .foregroundStyle(.appText.opacity(0.6))
        }
    }

    // MARK: - 検索結果

    @ViewBuilder
    private var resultSection: some View {
        switch viewModel.searchState {
        case .idle:
            EmptyView()
        case .searching:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
        case .notFound:
            messageText("ユーザーが見つかりませんでした。ユーザー名を確認してください。")
        case .failed(let message):
            messageText(message, isError: true)
        case .found(let result):
            VStack(alignment: .leading, spacing: 12) {
                FriendUserRow(user: result.user, avatarURL: viewModel.resultAvatarURL) {
                    relationAction(for: result.relation)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.appCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                if let message = viewModel.completionMessage {
                    messageText(message)
                }
                if let message = viewModel.sendErrorMessage {
                    messageText(message, isError: true)
                }
            }
        }
    }

    @ViewBuilder
    private func relationAction(for relation: FriendRelation) -> some View {
        switch relation {
        case .me:
            statusLabel("あなたです")
        case .friend:
            statusLabel("フレンド", systemImage: "checkmark")
        case .requested:
            statusLabel("申請済み", systemImage: "clock")
        case .incoming, .none:
            if viewModel.isSending {
                ProgressView()
            } else {
                Button {
                    Task { await sendRequest() }
                } label: {
                    // 相手から申請が来ている場合は、申請するとその場で承認になる。
                    Text(relation == .incoming ? "承認する" : "申請する")
                        .font(.system(size: 14, weight: .bold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.appPrimary)
            }
        }
    }

    // MARK: - 部品

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.appText.opacity(0.6))
    }

    private func statusLabel(_ title: String, systemImage: String? = nil) -> some View {
        Group {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(.appText.opacity(0.6))
    }

    private func messageText(_ message: String, isError: Bool = false) -> some View {
        Text(message)
            .font(.system(size: 13))
            .foregroundStyle(isError ? Color.red : Color.appText.opacity(0.7))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 操作

    private func search() async {
        guard viewModel.canSearch else { return }
        isQueryFocused = false
        await viewModel.search()
    }

    private func sendRequest() async {
        // フレンドが成立したら、相手からの申請が消えるのでバッジの件数を取り直す。
        if await viewModel.sendRequest() {
            await requestStore.refresh()
        }
    }
}

#Preview {
    NavigationStack {
        FriendAddView()
    }
    .environment(FriendRequestStore())
}
