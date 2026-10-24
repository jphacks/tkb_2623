import Foundation
import Testing
@testable import GourmetShareMap

@MainActor
struct ProfileViewModelTests {
    @Test func loadPopulatesDisplayNameBioAndStats() async throws {
        let profile = UserProfile(id: UUID(), name: "はる", bio: "麺が好きです", profileImage: nil)
        let stores = [
            makeStore(name: "店A", repeatNum: 2),
            makeStore(name: "店B", repeatNum: 5),
            makeStore(name: "店C", repeatNum: 1),
        ]
        let viewModel = ProfileViewModel(
            profileDataSource: FakeProfileDataSource(.success(profile)),
            storesDataSource: FakeStoresDataSource(.success(stores)),
            coverImagesDataSource: FakeCoverImagesDataSource()
        )
        await viewModel.load()

        #expect(viewModel.displayName == "はる")
        #expect(viewModel.bio == "麺が好きです")
        #expect(viewModel.storeCount == 3)
        #expect(viewModel.maxRepeatCount == 5)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isLoading == false)
    }

    @Test func loadFallsBackToEmptyDisplayNameWhenNameIsNil() async throws {
        let profile = UserProfile(id: UUID(), name: nil, bio: nil, profileImage: nil)
        let viewModel = ProfileViewModel(
            profileDataSource: FakeProfileDataSource(.success(profile)),
            storesDataSource: FakeStoresDataSource(.success([])),
            coverImagesDataSource: FakeCoverImagesDataSource()
        )
        await viewModel.load()

        #expect(viewModel.displayName == "")
        #expect(viewModel.bio == nil)
        #expect(viewModel.storeCount == 0)
        #expect(viewModel.maxRepeatCount == 0)
    }

    @Test func loadFriendCountIsAlwaysZero() async throws {
        let viewModel = ProfileViewModel(
            profileDataSource: FakeProfileDataSource(.success(makeProfile())),
            storesDataSource: FakeStoresDataSource(.success([makeStore(), makeStore()])),
            coverImagesDataSource: FakeCoverImagesDataSource()
        )
        #expect(viewModel.friendCount == 0)
        await viewModel.load()
        #expect(viewModel.friendCount == 0)
    }

    @Test func loadLimitsRecentRecordsToFirstFiveInFetchedOrder() async throws {
        // fetchStores()はcreated_at降順で返す前提のため、フェイクは既に並んだ順で返す。
        let stores = (1...7).map { makeStore(name: "店\($0)") }
        let viewModel = ProfileViewModel(
            profileDataSource: FakeProfileDataSource(.success(makeProfile())),
            storesDataSource: FakeStoresDataSource(.success(stores)),
            coverImagesDataSource: FakeCoverImagesDataSource()
        )
        await viewModel.load()

        #expect(viewModel.recentRecords.count == 5)
        #expect(viewModel.recentRecords.map(\.storeName) == ["店1", "店2", "店3", "店4", "店5"])
        #expect(viewModel.storeCount == 7)
    }

    @Test func loadFallsBackForNullCategoryAndReputation() async throws {
        let stores = [makeStore(name: "謎の店", category: nil, reputation: nil, repeatNum: 3)]
        let viewModel = ProfileViewModel(
            profileDataSource: FakeProfileDataSource(.success(makeProfile())),
            storesDataSource: FakeStoresDataSource(.success(stores)),
            coverImagesDataSource: FakeCoverImagesDataSource()
        )
        await viewModel.load()

        let record = try #require(viewModel.recentRecords.first)
        #expect(record.storeName == "謎の店")
        #expect(record.category == "未分類")
        #expect(record.rating == 0)
        #expect(record.repeatCount == 3)
    }

    @Test func loadSetsErrorMessageWhenProfileFetchFails() async throws {
        let viewModel = ProfileViewModel(
            profileDataSource: FakeProfileDataSource(.failure(FakeError(errorDescription: "プロフィール取得エラー"))),
            storesDataSource: FakeStoresDataSource(.success([])),
            coverImagesDataSource: FakeCoverImagesDataSource()
        )
        await viewModel.load()

        #expect(viewModel.errorMessage == "プロフィール取得エラー")
        #expect(viewModel.isLoading == false)
    }

    @Test func loadSetsErrorMessageWhenStoresFetchFails() async throws {
        let viewModel = ProfileViewModel(
            profileDataSource: FakeProfileDataSource(.success(makeProfile())),
            storesDataSource: FakeStoresDataSource(.failure(FakeError(errorDescription: "店舗取得エラー"))),
            coverImagesDataSource: FakeCoverImagesDataSource()
        )
        await viewModel.load()

        #expect(viewModel.errorMessage == "店舗取得エラー")
        #expect(viewModel.isLoading == false)
    }

    @Test func loadClearsPreviousErrorMessageOnRetry() async throws {
        let fakeProfile = FakeProfileDataSource(.failure(FakeError(errorDescription: "一時的な失敗")))
        let fakeStores = FakeStoresDataSource(.success([]))
        let viewModel = ProfileViewModel(
            profileDataSource: fakeProfile, storesDataSource: fakeStores,
            coverImagesDataSource: FakeCoverImagesDataSource()
        )
        await viewModel.load()
        #expect(viewModel.errorMessage == "一時的な失敗")

        fakeProfile.mode = .success(makeProfile(name: "復帰後"))
        await viewModel.load()
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.displayName == "復帰後")
    }

    @Test func loadSetsAvatarURLWhenProfileImageIsSet() async throws {
        let signedURL = URL(string: "https://example.com/signed/avatar.jpg")!
        let profile = makeProfile(profileImage: "11111111-1111-1111-1111-111111111111/icon.jpg")
        let fakeProfile = FakeProfileDataSource(.success(profile))
        fakeProfile.signedURLResult = .success(signedURL)
        let viewModel = ProfileViewModel(
            profileDataSource: fakeProfile,
            storesDataSource: FakeStoresDataSource(.success([])),
            coverImagesDataSource: FakeCoverImagesDataSource()
        )
        await viewModel.load()

        #expect(viewModel.avatarURL == signedURL)
        #expect(fakeProfile.lastSignedURLPath == "11111111-1111-1111-1111-111111111111/icon.jpg")
    }

    @Test func loadKeepsAvatarURLNilWhenProfileImageIsNil() async throws {
        let viewModel = ProfileViewModel(
            profileDataSource: FakeProfileDataSource(.success(makeProfile(profileImage: nil))),
            storesDataSource: FakeStoresDataSource(.success([])),
            coverImagesDataSource: FakeCoverImagesDataSource()
        )
        await viewModel.load()

        #expect(viewModel.avatarURL == nil)
    }

    @Test func loadFallsBackToNilAvatarURLWhenSigningFails() async throws {
        let fakeProfile = FakeProfileDataSource(.success(makeProfile(profileImage: "some/path.jpg")))
        fakeProfile.signedURLResult = .failure(FakeError(errorDescription: "署名URL取得エラー"))
        let viewModel = ProfileViewModel(
            profileDataSource: fakeProfile,
            storesDataSource: FakeStoresDataSource(.success([])),
            coverImagesDataSource: FakeCoverImagesDataSource()
        )
        await viewModel.load()

        // 署名URLの取得失敗は画面全体のエラーにはせず、アバターのみ固定アイコンにフォールバックする。
        #expect(viewModel.avatarURL == nil)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func loadSetsCoverImageURLsForRecentRecords() async throws {
        let withPhoto = makeStore(name: "写真あり")
        let withoutPhoto = makeStore(name: "写真なし")
        let coverURL = URL(string: "https://example.com/signed/cover.jpg")!
        let fakeCovers = FakeCoverImagesDataSource()
        fakeCovers.result = .success([withPhoto.id: coverURL])
        let viewModel = ProfileViewModel(
            profileDataSource: FakeProfileDataSource(.success(makeProfile())),
            storesDataSource: FakeStoresDataSource(.success([withPhoto, withoutPhoto])),
            coverImagesDataSource: fakeCovers
        )
        await viewModel.load()

        #expect(viewModel.recentRecords.map(\.coverImageURL) == [coverURL, nil])
        #expect(fakeCovers.lastStoreIDs == [withPhoto.id, withoutPhoto.id])
    }

    @Test func loadRequestsCoverImagesOnlyForRecentRecords() async throws {
        let stores = (1...7).map { makeStore(name: "店\($0)") }
        let fakeCovers = FakeCoverImagesDataSource()
        let viewModel = ProfileViewModel(
            profileDataSource: FakeProfileDataSource(.success(makeProfile())),
            storesDataSource: FakeStoresDataSource(.success(stores)),
            coverImagesDataSource: fakeCovers
        )
        await viewModel.load()

        #expect(fakeCovers.lastStoreIDs == stores.prefix(5).map(\.id))
    }

    @Test func loadFallsBackToNilCoverImageURLsWhenFetchFails() async throws {
        let fakeCovers = FakeCoverImagesDataSource()
        fakeCovers.result = .failure(FakeError(errorDescription: "表紙取得エラー"))
        let viewModel = ProfileViewModel(
            profileDataSource: FakeProfileDataSource(.success(makeProfile())),
            storesDataSource: FakeStoresDataSource(.success([makeStore(name: "店A")])),
            coverImagesDataSource: fakeCovers
        )
        await viewModel.load()

        // 表紙の取得失敗は画面全体のエラーにはせず、各行を固定アイコンにフォールバックする。
        #expect(viewModel.recentRecords.map(\.storeName) == ["店A"])
        #expect(viewModel.recentRecords.first?.coverImageURL == nil)
        #expect(viewModel.errorMessage == nil)
    }

    private func makeProfile(name: String? = "テスト太郎", bio: String? = nil, profileImage: String? = nil) -> UserProfile {
        UserProfile(id: UUID(), name: name, bio: bio, profileImage: profileImage)
    }

    private func makeStore(
        name: String = "テスト店",
        category: String? = "ラーメン",
        reputation: Double? = 4,
        repeatNum: Int = 1,
        createdAt: Date = Date()
    ) -> StoreRecord {
        StoreRecord(
            id: UUID(), name: name, category: category, reputation: reputation,
            userID: UUID(), googlePlaceID: nil, memo: nil, repeatNum: repeatNum,
            latitude: nil, longitude: nil, createdAt: createdAt
        )
    }
}

private struct FakeError: LocalizedError {
    let errorDescription: String?
}

@MainActor
private final class FakeProfileDataSource: ProfileProfileDataSource {
    enum Mode {
        case success(UserProfile)
        case failure(any Error)
    }

    var mode: Mode
    var signedURLResult: Result<URL, any Error> = .success(URL(string: "https://example.com/avatar.jpg")!)
    private(set) var lastSignedURLPath: String?

    init(_ mode: Mode) { self.mode = mode }

    func fetchMyProfile() async throws -> UserProfile {
        switch mode {
        case let .success(profile): return profile
        case let .failure(error): throw error
        }
    }

    func signedURL(path: String, expiresIn: Int) async throws -> URL {
        lastSignedURLPath = path
        return try signedURLResult.get()
    }
}

@MainActor
private final class FakeStoresDataSource: ProfileStoresDataSource {
    enum Mode {
        case success([StoreRecord])
        case failure(any Error)
    }

    var mode: Mode
    init(_ mode: Mode) { self.mode = mode }

    func fetchStores() async throws -> [StoreRecord] {
        switch mode {
        case let .success(stores): return stores
        case let .failure(error): throw error
        }
    }
}

@MainActor
private final class FakeCoverImagesDataSource: ProfileCoverImagesDataSource {
    var result: Result<[UUID: URL], any Error> = .success([:])
    private(set) var lastStoreIDs: [UUID]?

    func coverImageURLs(storeIDs: [UUID], expiresIn: Int) async throws -> [UUID: URL] {
        lastStoreIDs = storeIDs
        return try result.get()
    }
}
