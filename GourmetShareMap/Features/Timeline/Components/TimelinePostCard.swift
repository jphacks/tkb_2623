//
//  TimelinePostCard.swift
//  GourmetShareMap
//

import SwiftUI

/// 表紙の写真を背景に、投稿者・時刻・店名・カテゴリを重ねたカード。
struct TimelinePostCard: View {
    let post: TimelinePost
    let timeText: String
    var onTapLike: () -> Void = {}
    var onTapComments: () -> Void = {}

    private let cornerRadius: CGFloat = 18

    var body: some View {
        Color.clear
            .frame(height: 180)
            .background { coverImage }
            .overlay(alignment: .top) {
                // 白文字を読めるよう、上側だけ暗くする。
                LinearGradient(
                    colors: [.black.opacity(0.6), .black.opacity(0.25), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 130)
            }
            .overlay(alignment: .topLeading) { header.padding(14) }
            .overlay(alignment: .bottomTrailing) { memoLabel }
            .overlay(alignment: .bottomLeading) { actionRow.padding(12) }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
            .accessibilityElement(children: .combine)
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            likeButton
            commentButton
        }
    }

    private var likeButton: some View {
        Button(action: onTapLike) {
            HStack(spacing: 4) {
                Image(systemName: post.isLikedByMe ? "heart.fill" : "heart")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(post.likeCount)")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(post.isLikedByMe ? .pink : .white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.45), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var commentButton: some View {
        Button(action: onTapComments) {
            HStack(spacing: 4) {
                Image(systemName: "bubble.right")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(post.commentCount)")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.45), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                UserInitialAvatar(userID: post.userID, name: post.userName, imageURL: post.userAvatarURL)

                Text(post.userName ?? "名前未設定")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if post.isMine {
                    Text("自分")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.appPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white, in: Capsule())
                }

                Spacer(minLength: 8)

                Text(timeText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }

            HStack(spacing: 8) {
                Text(post.storeName)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let category = post.category, !category.isEmpty {
                    CategoryBadge(category: category)
                }
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }

    /// メモがあるときだけ右下に出す。写真の上でも読めるよう半透明の黒地に載せる。
    @ViewBuilder
    private var memoLabel: some View {
        if let memo = post.memo?.trimmingCharacters(in: .whitespacesAndNewlines), !memo.isEmpty {
            Text(memo)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.leading, 48)
                .padding(12)
        }
    }

    @ViewBuilder
    private var coverImage: some View {
        if let url = post.coverImageURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    /// 写真がない・読み込み中のときの背景。カテゴリのアイコンを薄く置く。
    private var placeholder: some View {
        LinearGradient(
            colors: [Color(hex: 0xC9A27E), Color(hex: 0x8A5A3B)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .bottomTrailing) {
            Image(.categoryIcon(for: post.category))
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .opacity(0.35)
                .padding(16)
        }
    }
}

/// ユーザーのアイコン。画像があればそれを、無い・読み込み中・失敗時は名前の頭文字を丸で囲んで表示する。
/// 頭文字の背景色はユーザーごとに固定。
struct UserInitialAvatar: View {
    let userID: UUID
    let name: String?
    var imageURL: URL?

    private let size: CGFloat = 30

    private static let palette: [Color] = [
        Color(hex: 0xF6C9B4), Color(hex: 0xF7DFA8), Color(hex: 0xC8DDF2),
        Color(hex: 0xCFE5C6), Color(hex: 0xE5D1F0),
    ]

    var body: some View {
        initial
            .overlay {
                if let imageURL {
                    AsyncImage(url: imageURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Color.clear
                        }
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
    }

    private var initial: some View {
        Text(name?.first.map(String.init) ?? "?")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.appText)
            .frame(width: size, height: size)
            .background(backgroundColor, in: Circle())
    }

    private var backgroundColor: Color {
        // hashValue は起動ごとに変わるので、UUID のバイトから色を決める。
        let index = withUnsafeBytes(of: userID.uuid) { $0.reduce(0) { $0 &+ Int($1) } }
        return Self.palette[index % Self.palette.count]
    }
}

#Preview {
    VStack(spacing: 16) {
        TimelinePostCard(
            post: TimelinePost(
                id: UUID(), storeName: "カフェ つむぎ", category: "カフェ・喫茶",
                memo: "ラテアートがかわいい。季節のタルトもおすすめ", userID: UUID(),
                userName: "あおい", userAvatarURL: nil, isMine: false, createdAt: .now, coverImageURL: nil,
                commentCount: 3, likeCount: 5, isLikedByMe: true
            ),
            timeText: "2時間前"
        )
        TimelinePostCard(
            post: TimelinePost(
                id: UUID(), storeName: "麺屋 はる", category: "ラーメン・麺類", memo: nil, userID: UUID(),
                userName: "はる", userAvatarURL: nil, isMine: true, createdAt: .now, coverImageURL: nil,
                commentCount: 0, likeCount: 0, isLikedByMe: false
            ),
            timeText: "5時間前"
        )
    }
    .padding()
    .background(.appBackground)
}
