import Foundation
import Supabase

@MainActor
final class RecommendationRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    convenience init() {
        self.init(client: SupabaseManager.shared.client)
    }

    /// Coordinates come from the caller. An explicit area overrides the center
    /// on the server. Auth, cancellation and transport errors propagate unchanged.
    func recommend(_ input: RecommendationInput) async throws -> RecommendationResult {
        let genre = input.genre.trimmingCharacters(in: .whitespacesAndNewlines)
        let area = input.area?.trimmingCharacters(in: .whitespacesAndNewlines)
        // JavaScript measures input limits in UTF-16 code units.
        guard !genre.isEmpty, genre.utf16.count <= 200,
              (input.area?.utf16.count ?? 0) <= 200,
              input.latitude.isFinite, (-90...90).contains(input.latitude),
              input.longitude.isFinite, (-180...180).contains(input.longitude) else {
            throw RecommendationError.invalidInput
        }
        let session = try await client.auth.session
        let payload = RecommendationInput(
            genre: genre, latitude: input.latitude, longitude: input.longitude,
            area: area.flatMap { $0.isEmpty ? nil : $0 }
        )
        do {
            // Give the server's 60-second deadline time to return its error body.
            let result: RecommendationResult = try await client.functions.invoke(
                "recommend-shop",
                options: .init(
                    method: .post,
                    headers: ["Authorization": "Bearer \(session.accessToken)"],
                    body: payload,
                    timeoutInterval: 65
                )
            )
            let shop = result.recommendation
            func validAttribution(_ source: RecommendationAttribution) -> Bool {
                !source.provider.isEmpty && !source.name.isEmpty &&
                    source.url.scheme == "https" && source.url.host != nil &&
                    source.url.user == nil && source.url.password == nil
            }
            guard !shop.placeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !shop.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  shop.latitude.isFinite, (-90...90).contains(shop.latitude),
                  shop.longitude.isFinite, (-180...180).contains(shop.longitude),
                  !result.attributions.isEmpty,
                  result.attributions.allSatisfy(validAttribution) else {
                throw RecommendationError.invalidResponse
            }
            return result
        } catch let FunctionsError.httpError(code, data) {
            guard let envelope = try? JSONDecoder().decode(RecommendationErrorEnvelope.self, from: data) else {
                throw RecommendationError.invalidResponse
            }
            throw RecommendationError.api(statusCode: code, error: envelope.error)
        } catch is DecodingError {
            throw RecommendationError.invalidResponse
        }
    }
}

private nonisolated struct RecommendationErrorEnvelope: Decodable {
    let error: RecommendationAPIError
}
