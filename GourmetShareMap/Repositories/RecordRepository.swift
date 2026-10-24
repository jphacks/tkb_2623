import Foundation
import Supabase

enum StoreSaveError: LocalizedError, Equatable {
    case invalidName
    case invalidCategory
    case invalidReputation
    case invalidRepeatNum
    case invalidCoordinate
    case notFound
    case ambiguousGooglePlaceID

    var errorDescription: String? {
        switch self {
        case .invalidName: return "店舗名を入力してください。"
        case .invalidCategory: return "カテゴリを入力してください。"
        case .invalidReputation: return "評価は1〜5の整数で指定してください。"
        case .invalidRepeatNum: return "訪問回数は1以上で指定してください。"
        case .invalidCoordinate: return "緯度・経度の値が不正です。"
        case .notFound: return "更新できる店舗記録が見つかりません。"
        case .ambiguousGooglePlaceID: return "同じGoogle店舗の記録が複数あります。更新する記録のIDを指定してください。"
        }
    }
}

/// マップに表示する店舗一覧と、その取得に使ったログインユーザーのID。
/// 自分の店舗とフレンドの店舗をピンの色などで出し分けるために、IDを同梱する。
nonisolated struct VisibleStores: Sendable {
    let currentUserID: UUID
    let stores: [StoreRecord]
}

@MainActor
final class RecordRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    convenience init() {
        self.init(client: SupabaseManager.shared.client)
    }

    /// マップ・プロフィール共通の、自分の店舗記録一覧。座標がNULLの行も返す。
    /// created_at降順・id昇順。Supabase標準の最大返却件数に合わせてページ取得する。
    func fetchStores() async throws -> [StoreRecord] {
        let userID = try await client.auth.session.user.id
        let pageSize = 1000
        var records: [StoreRecord] = []
        while true {
            let page: [StoreRecord] = try await client.from("store")
                .select()
                .eq("user_id", value: userID)
                .order("created_at", ascending: false)
                .order("id", ascending: true)
                .range(from: records.count, to: records.count + pageSize - 1)
                .execute().value
            records.append(contentsOf: page)
            if page.count < pageSize { return records }
        }
    }

    /// マップ向けの、自分とフレンド（自分がフォローしている相手）の店舗記録一覧。
    /// フレンドの行は`store`のSELECT RLSポリシー（自分の行 or フォロー相手の行）で返るため、
    /// クエリ側では`user_id`で絞り込まない。`fetchStores()`との違いはこの絞り込みの有無だけ。
    /// `fetchStores()`と同様に座標がNULLの行も返すので、ピン表示側で座標のある行を選ぶ。
    /// 自分の店舗とフレンドの店舗の判別用に、認証の往復を増やさず同じセッションの
    /// ユーザーIDを`VisibleStores.currentUserID`として返す。
    /// created_at降順・id昇順。Supabase標準の最大返却件数に合わせてページ取得する。
    func fetchVisibleStores() async throws -> VisibleStores {
        let currentUserID = try await client.auth.session.user.id
        let pageSize = 1000
        var records: [StoreRecord] = []
        while true {
            let page: [StoreRecord] = try await client.from("store")
                .select()
                .order("created_at", ascending: false)
                .order("id", ascending: true)
                .range(from: records.count, to: records.count + pageSize - 1)
                .execute().value
            records.append(contentsOf: page)
            if page.count < pageSize {
                return VisibleStores(currentUserID: currentUserID, stores: records)
            }
        }
    }

    /// 自分の店舗記録を登録・更新し、DBが返す保存結果を返す。
    /// 入力は全体を上書きする。認証・通信・DB・デコードエラーは呼び出し元へ伝える。
    func saveStore(_ input: StoreSaveInput) async throws -> StoreRecord {
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = input.category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw StoreSaveError.invalidName }
        guard !category.isEmpty else { throw StoreSaveError.invalidCategory }
        if let reputation = input.reputation, !(1...5).contains(reputation) {
            throw StoreSaveError.invalidReputation
        }
        guard input.repeatNum >= 1 else { throw StoreSaveError.invalidRepeatNum }
        guard input.latitude.isFinite, (-90...90).contains(input.latitude),
              input.longitude.isFinite, (-180...180).contains(input.longitude) else {
            throw StoreSaveError.invalidCoordinate
        }

        let session = try await client.auth.session
        let placeID = input.googlePlaceID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = StoreSavePayload(
            name: name, category: category, reputation: input.reputation,
            userID: session.user.id,
            googlePlaceID: placeID.flatMap { $0.isEmpty ? nil : $0 },
            memo: input.memo, repeatNum: input.repeatNum,
            latitude: input.latitude, longitude: input.longitude
        )

        if let id = input.id {
            return try await updateStore(id: id, payload: payload)
        }

        if let placeID = payload.googlePlaceID {
            // 既存storeに複合一意制約はないため、検索してからIDで更新する。
            // 同時リクエストの重複登録はDBの変更なしには完全には防げない。
            let matches: [ExistingStoreID] = try await client.from("store")
                .select("id")
                .eq("user_id", value: session.user.id)
                .eq("google_place_id", value: placeID)
                .limit(2)
                .execute().value
            guard matches.count <= 1 else { throw StoreSaveError.ambiguousGooglePlaceID }
            if let match = matches.first {
                return try await updateStore(id: match.id, payload: payload)
            }
        }

        return try await client.from("store")
            .insert(payload)
            .select().single().execute().value
    }

    private func updateStore(id: UUID, payload: StoreSavePayload) async throws -> StoreRecord {
        let records: [StoreRecord] = try await client.from("store")
            .update(payload)
            .eq("id", value: id)
            .eq("user_id", value: payload.userID)
            .select().execute().value
        guard let record = records.first else { throw StoreSaveError.notFound }
        return record
    }
}

private nonisolated struct ExistingStoreID: Decodable {
    let id: UUID
}

/// id / created_atを送らないことで、更新時にもDB上の値を保持する。
private nonisolated struct StoreSavePayload: Encodable {
    let name: String
    let category: String
    let reputation: Int?
    let userID: UUID
    let googlePlaceID: String?
    let memo: String?
    let repeatNum: Int
    let latitude: Double
    let longitude: Double

    enum CodingKeys: String, CodingKey {
        case name, category, reputation, memo, latitude, longitude
        case userID = "user_id"
        case googlePlaceID = "google_place_id"
        case repeatNum = "repeat_num"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(category, forKey: .category)
        // encodeIfPresentだとnilの項目が省略され、既存値を削除できない。
        try container.encode(reputation, forKey: .reputation)
        try container.encode(userID, forKey: .userID)
        try container.encode(googlePlaceID, forKey: .googlePlaceID)
        try container.encode(memo, forKey: .memo)
        try container.encode(repeatNum, forKey: .repeatNum)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }
}
