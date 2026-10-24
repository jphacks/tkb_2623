//
//  ProfileViewModel.swift
//  GourmetShareMap
//

import Combine
import Foundation

struct ProfileRecord: Identifiable {
    let id = UUID()
    let storeName: String
    let category: String
    let rating: Double
    let repeatCount: Int
}

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published private(set) var displayName: String
    @Published private(set) var storeCount: Int
    @Published private(set) var maxRepeatCount: Int
    @Published private(set) var friendCount: Int
    @Published private(set) var recentRecords: [ProfileRecord]

    // TODO: user / store テーブルにデータが入り次第、UserRepository経由の取得に差し替える。
    // 現状はDBが空のため仮データを表示している。
    init(
        displayName: String = "はる",
        storeCount: Int = 24,
        maxRepeatCount: Int = 8,
        friendCount: Int = 12,
        recentRecords: [ProfileRecord] = [
            ProfileRecord(storeName: "麺屋 はる", category: "ラーメン", rating: 4, repeatCount: 3),
            ProfileRecord(storeName: "洋食キッチン 青", category: "洋食", rating: 4, repeatCount: 2),
        ]
    ) {
        self.displayName = displayName
        self.storeCount = storeCount
        self.maxRepeatCount = maxRepeatCount
        self.friendCount = friendCount
        self.recentRecords = recentRecords
    }
}
