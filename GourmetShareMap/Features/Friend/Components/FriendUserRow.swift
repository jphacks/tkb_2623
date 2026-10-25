//
//  FriendUserRow.swift
//  GourmetShareMap
//

import SwiftUI

/// アイコン・表示名・user_name を並べた1行。右端に申請ボタンなどを置ける。
struct FriendUserRow<Trailing: View>: View {
    let user: FriendUser
    let avatarURL: URL?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatarPreview(previewURL: avatarURL, pendingImageData: nil, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.appText)
                    .lineLimit(1)
                Text("@\(user.userName)")
                    .font(.system(size: 13))
                    .foregroundStyle(.appText.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            trailing
        }
        .padding(.vertical, 4)
    }
}

extension FriendUserRow where Trailing == EmptyView {
    init(user: FriendUser, avatarURL: URL?) {
        self.init(user: user, avatarURL: avatarURL) { EmptyView() }
    }
}

#Preview {
    List {
        FriendUserRow(
            user: FriendUser(id: UUID(), userName: "haru_123", name: "はる", profileImage: nil),
            avatarURL: nil
        )
        FriendUserRow(
            user: FriendUser(id: UUID(), userName: "aoi", name: nil, profileImage: nil),
            avatarURL: nil
        ) {
            Button("承認") {}
                .buttonStyle(.borderedProminent)
        }
    }
}
