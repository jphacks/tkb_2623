//
//  IncomingFriendRequestRow.swift
//  GourmetShareMap
//

import SwiftUI

/// 受け取ったフレンド申請の1行。承認・拒否のボタンを持つ。
struct IncomingFriendRequestRow: View {
    let request: FriendRequest
    let avatarURL: URL?
    let isProcessing: Bool
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        FriendUserRow(user: request.requester, avatarURL: avatarURL) {
            if isProcessing {
                ProgressView()
            } else {
                HStack(spacing: 8) {
                    Button("拒否", action: onReject)
                        .buttonStyle(.bordered)
                        .tint(.appText.opacity(0.6))
                    Button("承認", action: onAccept)
                        .buttonStyle(.borderedProminent)
                        .tint(.appPrimary)
                }
                .font(.system(size: 14, weight: .bold))
            }
        }
    }
}

#Preview {
    List {
        IncomingFriendRequestRow(
            request: FriendRequest(
                requester: FriendUser(id: UUID(), userName: "haru_123", name: "はる", profileImage: nil),
                createdAt: .now
            ),
            avatarURL: nil,
            isProcessing: false,
            onAccept: {},
            onReject: {}
        )
    }
}
