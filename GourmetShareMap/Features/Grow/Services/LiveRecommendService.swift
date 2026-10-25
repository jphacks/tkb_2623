//
//  LiveRecommendService.swift
//  GourmetShareMap
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Supabase

enum RecommendServiceError: LocalizedError, Equatable {
    case invalidResponse
    case server(message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "レコメンドのレスポンスが不正です。"
        case let .server(message): return message
        }
    }
}

/// 本番の実装。Supabaseの `ai-recommend` Edge Function（Cloud Run上のAIバックエンドへの中継）を呼ぶ。
/// APIキーはアプリに持たせず、ログイン中ユーザーのSupabaseアクセストークンだけで呼び出す。
struct LiveRecommendService: RecommendServing {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseManager.shared.client) {
        self.client = client
    }

    /// `ai_model_status`（Edge Functionが学習結果を書き込む）を直接読む。
    /// レコメンドをまだ一度も試していなければ行が無く、精度は表示しない。
    func fetchModelStats(records: [StoreRecord]) async throws -> ModelStats {
        let userID = try await client.auth.session.user.id
        let rows: [AIModelStatusRow] = try await client.from("ai_model_status")
            .select("record_count, mean_abs_error")
            .eq("user_id", value: userID)
            .limit(1)
            .execute().value
        guard let row = rows.first else {
            return ModelStats(trainedRecordCount: records.count, meanAbsoluteError: nil)
        }
        return ModelStats(trainedRecordCount: row.recordCount, meanAbsoluteError: row.meanAbsError)
    }

    func recommend(freeText: String, latitude: Double, longitude: Double, records: [StoreRecord]) async throws -> [Recommendation] {
        let session = try await client.auth.session
        var request = URLRequest(url: SupabaseConfig.url.appendingPathComponent("functions/v1/ai-recommend"))
        request.httpMethod = "POST"
        // Cloud Runのコールドスタート+Gemini/Places/CLIPの直列呼び出しのため長めに取る。
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "free_text": freeText,
            "lat": latitude,
            "lng": longitude,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RecommendServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(EdgeFunctionErrorBody.self, from: data))?.message
                ?? "レコメンドの取得に失敗しました (HTTP \(http.statusCode))"
            throw RecommendServiceError.server(message: message)
        }

        let decoded = try JSONDecoder().decode(RecommendResponseBody.self, from: data)
        return decoded.predictions.map { prediction in
            let category = prediction.category ?? "その他"
            return Recommendation(
                placeID: prediction.placeID,
                name: prediction.name ?? "名称不明の店舗",
                category: category,
                predictedRating: prediction.predictedRating,
                reason: "「\(freeText)」に近い、\(category)のお店だと思います。"
            )
        }
    }
}

private nonisolated struct AIModelStatusRow: Decodable {
    let recordCount: Int
    let meanAbsError: Double?

    enum CodingKeys: String, CodingKey {
        case recordCount = "record_count"
        case meanAbsError = "mean_abs_error"
    }
}

/// Edge Function由来のエラーは`error`キー、Cloud Run(FastAPI)から素通りした
/// エラーは`detail`キーを使う(レート制限の429など)。両対応で拾う。
private nonisolated struct EdgeFunctionErrorBody: Decodable {
    let message: String?

    enum CodingKeys: String, CodingKey {
        case error, detail
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decodeIfPresent(String.self, forKey: .error)
            ?? container.decodeIfPresent(String.self, forKey: .detail)
    }
}

private nonisolated struct RecommendResponseBody: Decodable {
    let predictions: [Prediction]

    struct Prediction: Decodable {
        let placeID: String
        let name: String?
        let category: String?
        let predictedRating: Double

        enum CodingKeys: String, CodingKey {
            case placeID = "place_id"
            case name, category
            case predictedRating = "predicted_rating"
        }
    }
}
