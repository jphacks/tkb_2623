import Foundation
import Testing
@testable import GourmetShareMap

@MainActor
struct FriendListViewModelTests {
    @Test func loadPopulatesFriendsAndAvatarURLs() async {
        let fake = FakeFriendDataSource()
        let avatarURL = URL(string: "https://example.com/a.jpg")!
        let withIcon = makeFriendUser("aoi", name: "あおい", profileImage: "u/a.jpg")
        let withoutIcon = makeFriendUser("haru")
        fake.friendsResult = .success([withIcon, withoutIcon])
        fake.signedURLs = ["u/a.jpg": avatarURL]
        let viewModel = FriendListViewModel(repository: fake)

        await viewModel.load()

        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.friends == [withIcon, withoutIcon])
        #expect(viewModel.avatarURL(for: withIcon) == avatarURL)
        #expect(viewModel.avatarURL(for: withoutIcon) == nil)
    }

    @Test func loadWithNoFriendsIsLoadedAndEmpty() async {
        let viewModel = FriendListViewModel(repository: FakeFriendDataSource())

        await viewModel.load()

        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.friends.isEmpty)
    }

    @Test func loadFailureSetsFailedState() async {
        let fake = FakeFriendDataSource()
        fake.friendsResult = .failure(FakeFriendError(errorDescription: "通信エラー"))
        let viewModel = FriendListViewModel(repository: fake)

        await viewModel.load()

        #expect(viewModel.loadState == .failed("通信エラー"))
    }

    @Test func displayNameFallsBackToUserName() {
        #expect(makeFriendUser("aoi", name: "あおい").displayName == "あおい")
        #expect(makeFriendUser("aoi", name: nil).displayName == "aoi")
        #expect(makeFriendUser("aoi", name: "  ").displayName == "aoi")
    }
}
