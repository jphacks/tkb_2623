import Foundation
import Testing
@testable import GourmetShareMap

@MainActor
struct ProfileEditViewModelTests {
    @Test func loadPopulatesNameBioAndAvatarPreviewURL() async throws {
        let signedURL = URL(string: "https://example.com/signed/old-icon.jpg")!
        let fake = FakeProfileEditDataSource(
            profile: .success(makeProfile(name: "はる", bio: "麺が好きです", profileImage: "u/old-icon.jpg"))
        )
        fake.signedURLResult = .success(signedURL)
        let viewModel = ProfileEditViewModel(dataSource: fake)

        await viewModel.load()

        #expect(viewModel.name == "はる")
        #expect(viewModel.bio == "麺が好きです")
        #expect(viewModel.avatarPreviewURL == signedURL)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func loadFallsBackToEmptyStringsWhenNameAndBioAreNil() async throws {
        let fake = FakeProfileEditDataSource(profile: .success(makeProfile(name: nil, bio: nil, profileImage: nil)))
        let viewModel = ProfileEditViewModel(dataSource: fake)

        await viewModel.load()

        #expect(viewModel.name == "")
        #expect(viewModel.bio == "")
        #expect(viewModel.avatarPreviewURL == nil)
    }

    @Test func loadSetsErrorMessageOnFetchFailure() async throws {
        let fake = FakeProfileEditDataSource(profile: .failure(FakeError(errorDescription: "取得エラー")))
        let viewModel = ProfileEditViewModel(dataSource: fake)

        await viewModel.load()

        #expect(viewModel.errorMessage == "取得エラー")
        #expect(viewModel.isLoading == false)
    }

    @Test func saveCallsUpdateMyProfileWithTrimmedValues() async throws {
        let fake = FakeProfileEditDataSource(profile: .success(makeProfile()))
        let viewModel = ProfileEditViewModel(dataSource: fake)
        viewModel.name = " 新しい名前 "
        viewModel.bio = " 自己紹介\n"

        await viewModel.save()

        #expect(fake.lastUpdateName == "新しい名前")
        #expect(fake.lastUpdateBio == "自己紹介")
        #expect(viewModel.didSaveSuccessfully == true)
        #expect(viewModel.isSaving == false)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func saveDoesNotUploadImageWhenNoPendingImage() async throws {
        let fake = FakeProfileEditDataSource(profile: .success(makeProfile()))
        let viewModel = ProfileEditViewModel(dataSource: fake)

        await viewModel.save()

        #expect(fake.uploadCallCount == 0)
        #expect(viewModel.didSaveSuccessfully == true)
    }

    @Test func saveUploadsImageWhenPendingImageIsSetAndUpdatesPreview() async throws {
        let newURL = URL(string: "https://example.com/signed/new-icon.jpg")!
        let fake = FakeProfileEditDataSource(profile: .success(makeProfile()))
        fake.uploadResult = .success("u/new-icon.jpg")
        fake.signedURLResult = .success(newURL)
        let viewModel = ProfileEditViewModel(dataSource: fake)
        let imageData = Data([1, 2, 3])
        viewModel.selectImage(data: imageData, format: .png)

        await viewModel.save()

        #expect(fake.uploadCallCount == 1)
        #expect(fake.lastUploadData == imageData)
        #expect(fake.lastUploadFormat == .png)
        #expect(viewModel.pendingImageData == nil)
        #expect(viewModel.avatarPreviewURL == newURL)
        #expect(viewModel.didSaveSuccessfully == true)
        // uploadProfileImage自体がuser.profile_imageを更新するため、二重更新はしない。
        // このViewModelはupdateMyProfileImageに依存していないため、呼び出す手段を持たない。
    }

    @Test func saveSetsErrorMessageAndSkipsUploadWhenProfileUpdateFails() async throws {
        let fake = FakeProfileEditDataSource(profile: .success(makeProfile()))
        fake.updateResult = .failure(FakeError(errorDescription: "更新エラー"))
        let viewModel = ProfileEditViewModel(dataSource: fake)
        viewModel.selectImage(data: Data([1]))

        await viewModel.save()

        #expect(viewModel.errorMessage == "更新エラー")
        #expect(viewModel.didSaveSuccessfully == false)
        #expect(fake.uploadCallCount == 0)
        // 画像アップロードに進まなかったため、選択済み画像は保持されたままになる。
        #expect(viewModel.pendingImageData != nil)
    }

    @Test func saveSetsErrorMessageAndKeepsPendingImageWhenUploadFails() async throws {
        let fake = FakeProfileEditDataSource(profile: .success(makeProfile()))
        fake.uploadResult = .failure(FakeError(errorDescription: "アップロードエラー"))
        let viewModel = ProfileEditViewModel(dataSource: fake)
        let imageData = Data([1, 2, 3])
        viewModel.selectImage(data: imageData)

        await viewModel.save()

        #expect(viewModel.errorMessage == "アップロードエラー")
        #expect(viewModel.didSaveSuccessfully == false)
        // 再試行できるよう、失敗した画像データは保持したままにする。
        #expect(viewModel.pendingImageData == imageData)
    }

    @Test func selectImageAndCancelPendingImage() async throws {
        let fake = FakeProfileEditDataSource(profile: .success(makeProfile()))
        let viewModel = ProfileEditViewModel(dataSource: fake)
        let imageData = Data([9, 9])

        viewModel.selectImage(data: imageData)
        #expect(viewModel.pendingImageData == imageData)

        viewModel.cancelPendingImage()
        #expect(viewModel.pendingImageData == nil)
    }

    private func makeProfile(
        name: String? = "テスト太郎", bio: String? = "よろしくお願いします", profileImage: String? = nil
    ) -> UserProfile {
        UserProfile(id: UUID(), name: name, bio: bio, profileImage: profileImage)
    }
}

private struct FakeError: LocalizedError {
    let errorDescription: String?
}

@MainActor
private final class FakeProfileEditDataSource: ProfileEditDataSource {
    var profile: Result<UserProfile, any Error>
    var updateResult: Result<Void, any Error> = .success(())
    var uploadResult: Result<String, any Error> = .success("u/uploaded.jpg")
    var signedURLResult: Result<URL, any Error> = .success(URL(string: "https://example.com/avatar.jpg")!)

    private(set) var lastUpdateName: String?
    private(set) var lastUpdateBio: String?
    private(set) var uploadCallCount = 0
    private(set) var lastUploadData: Data?
    private(set) var lastUploadFormat: RecordImageFormat?

    init(profile: Result<UserProfile, any Error>) { self.profile = profile }

    func fetchMyProfile() async throws -> UserProfile { try profile.get() }

    func updateMyProfile(name: String?, bio: String?) async throws {
        lastUpdateName = name
        lastUpdateBio = bio
        try updateResult.get()
    }

    func uploadProfileImage(data: Data, format: RecordImageFormat) async throws -> String {
        uploadCallCount += 1
        lastUploadData = data
        lastUploadFormat = format
        return try uploadResult.get()
    }

    func signedURL(path: String, expiresIn: Int) async throws -> URL {
        try signedURLResult.get()
    }
}
