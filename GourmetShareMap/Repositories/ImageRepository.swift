import Foundation
import Supabase

@MainActor
final class ImageRepository {
    private let client: SupabaseClient
    private let bucket = "record-images"

    init(client: SupabaseClient) { self.client = client }
    convenience init() { self.init(client: SupabaseManager.shared.client) }

    /// JPEG/PNGにエンコード済みのデータを、対応するformatとともに渡す。
    func uploadImage(data: Data, storeID: UUID, format: RecordImageFormat = .jpeg) async throws -> ImageRecord {
        guard !data.isEmpty else { throw ImageRepositoryError.emptyData }
        let userID = try await client.auth.session.user.id
        try await requireOwnedStore(storeID, userID: userID)
        let path = "\(userID.uuidString.lowercased())/\(storeID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).\(format.fileExtension)"
        try await client.storage.from(bucket).upload(path, data: data,
            options: FileOptions(contentType: format.contentType, upsert: false))
        do {
            return try await client.from("image")
                .insert(ImageInsert(storeID: storeID, path: path))
                .select().single().execute().value
        } catch {
            let insertionError = error
            do { try await client.storage.from(bucket).remove(paths: [path]) }
            catch {
                throw ImageRepositoryError.cleanupFailed(path: path, insertionError: insertionError, cleanupError: error)
            }
            throw insertionError
        }
    }

    /// 本人・フレンドの閲覧権限はDBとStorageの両方のRLSで検証される。
    func signedURL(imageID: UUID, expiresIn: Int = 3600) async throws -> URL {
        guard expiresIn > 0 else { throw ImageRepositoryError.invalidExpiration }
        _ = try await client.auth.session
        let image = try await fetchImage(imageID)
        return try await client.storage.from(bucket).createSignedURL(path: image.path, expiresIn: expiresIn)
    }

    /// Storageを先に削除する。DB削除失敗時は同じimageIDで再試行できる。
    func deleteImage(imageID: UUID) async throws {
        let userID = try await client.auth.session.user.id
        let image = try await fetchImage(imageID)
        try await requireOwnedStore(image.storeID, userID: userID)
        // DBの不正なパスが別店舗・別ユーザーのファイルを指していても削除しない。
        let parts = image.path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0] == userID.uuidString.lowercased(),
              parts[1] == image.storeID.uuidString.lowercased(),
              !parts[2].isEmpty, parts[2] != ".", parts[2] != ".." else {
            throw ImageRepositoryError.invalidPath
        }
        do { try await client.storage.from(bucket).remove(paths: [image.path]) }
        catch let error as StorageError where error.statusCode == "404" {
            // 既に削除されたオブジェクトは、DB行の削除だけで完了する。
        }
        let deleted: [DeletedImageID] = try await client.from("image").delete()
            .eq("id", value: image.id).eq("store_id", value: image.storeID)
            .select("id").execute().value
        guard !deleted.isEmpty else { throw ImageRepositoryError.imageNotFound }
    }

    private func fetchImage(_ id: UUID) async throws -> ImageRecord {
        let images: [ImageRecord] = try await client.from("image").select()
            .eq("id", value: id).limit(1).execute().value
        guard let image = images.first else { throw ImageRepositoryError.imageNotFound }
        return image
    }

    private func requireOwnedStore(_ id: UUID, userID: UUID) async throws {
        let stores: [OwnedImageStore] = try await client.from("store").select("id")
            .eq("id", value: id).eq("user_id", value: userID).limit(1).execute().value
        guard !stores.isEmpty else { throw ImageRepositoryError.storeNotOwned }
    }
}

private nonisolated struct OwnedImageStore: Decodable { let id: UUID }
private nonisolated struct DeletedImageID: Decodable { let id: UUID }
private nonisolated struct ImageInsert: Encodable {
    let storeID: UUID
    let path: String
    enum CodingKeys: String, CodingKey {
        case storeID = "store_id"
        case path = "image"
    }
}
