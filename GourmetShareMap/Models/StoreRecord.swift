import Foundation

/// ユーザーごとの店舗記録。既存DBの `store` に対応する。
nonisolated struct StoreRecord: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let category: String?
    let reputation: Double?
    let userID: UUID
    let googlePlaceID: String?
    let memo: String?
    let repeatNum: Int
    let latitude: Double?
    let longitude: Double?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, category, reputation, memo, latitude, longitude
        case userID = "user_id"
        case googlePlaceID = "google_place_id"
        case repeatNum = "repeat_num"
        case createdAt = "created_at"
    }
}

/// 全項目の保存入力。nilの評価・メモ・Google店舗IDは既存値を消す。
/// 手入力店舗の編集には、保存結果のidを渡す。
struct StoreSaveInput: Sendable {
    var id: UUID? = nil
    var name: String
    var category: String
    var reputation: Int? = nil
    var googlePlaceID: String? = nil
    var memo: String? = nil
    /// 初回を含む訪問回数。再保存しても自動加算しない。
    var repeatNum: Int = 1
    var latitude: Double
    var longitude: Double
}
