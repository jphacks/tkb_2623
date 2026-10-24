//
//  TimelineNoFriendsView.swift
//  GourmetShareMap
//

import SwiftUI

/// フレンドがいなくて、表示する記録もないときの空状態。
struct TimelineNoFriendsView: View {
    let onFindFriends: () -> Void
    let onCreateRecord: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "person.2")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.appPrimary)
                .frame(width: 112, height: 112)
                .background(Color.appPrimary.opacity(0.12), in: Circle())
                .padding(.bottom, 24)

            Text("フレンドの記録がまだありません")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.appText)
                .padding(.bottom, 14)

            Text("フレンドを追加すると、みんなが行ったお店がここに新しい順で流れてきます。")
                .font(.system(size: 14))
                .foregroundStyle(.appText.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.bottom, 28)

            Button(action: onFindFriends) {
                Label("フレンドを探す", systemImage: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(.appPrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.bottom, 24)

            Button(action: onCreateRecord) {
                Text("先に自分の記録を登録する")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.appPrimary)
                    .underline()
            }
        }
        .padding(.horizontal, 32)
    }
}

#Preview {
    TimelineNoFriendsView(onFindFriends: {}, onCreateRecord: {})
        .frame(maxHeight: .infinity)
        .background(.appBackground)
}
