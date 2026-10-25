import Foundation
import Testing
@testable import GourmetShareMap

@MainActor
private final class FakeMyProfileSource: MyProfileFetching {
    var result: Result<UserProfile, any Error>

    init(result: Result<UserProfile, any Error>) { self.result = result }

    func fetchMyProfile() async throws -> UserProfile { try result.get() }
}

@MainActor
struct FriendAddViewModelTests {
    private func makeViewModel(
        _ fake: FakeFriendDataSource,
        profile: Result<UserProfile, any Error> = .success(
            UserProfile(id: UUID(), userName: "me_123", name: "自分", bio: nil, profileImage: nil)
        )
    ) -> FriendAddViewModel {
        FriendAddViewModel(repository: fake, profileSource: FakeMyProfileSource(result: profile))
    }

    private func found(_ relation: FriendRelation, user: FriendUser = makeFriendUser("haru_01", name: "はる")) -> FriendSearchResult {
        FriendSearchResult(user: user, relation: relation)
    }

    // MARK: - 自分のユーザー名

    @Test func loadMyUserName() async {
        let viewModel = makeViewModel(FakeFriendDataSource())
        await viewModel.loadMyUserName()
        #expect(viewModel.myUserName == "me_123")
    }

    @Test func loadMyUserNameFailureLeavesNil() async {
        let viewModel = makeViewModel(FakeFriendDataSource(), profile: .failure(FakeFriendError(errorDescription: "x")))
        await viewModel.loadMyUserName()
        #expect(viewModel.myUserName == nil)
    }

    // MARK: - 検索

    @Test func queryIsLowercasedWhileTyping() {
        let viewModel = makeViewModel(FakeFriendDataSource())
        viewModel.query = "Haru_01"
        #expect(viewModel.query == "haru_01")
    }

    @Test func searchFoundSetsResultAndAvatar() async {
        let fake = FakeFriendDataSource()
        let avatarURL = URL(string: "https://example.com/h.jpg")!
        let user = makeFriendUser("haru_01", name: "はる", profileImage: "u/h.jpg")
        fake.searchResult = .success(found(.none, user: user))
        fake.signedURLs = ["u/h.jpg": avatarURL]
        let viewModel = makeViewModel(fake)
        viewModel.query = " haru_01 "

        await viewModel.search()

        #expect(fake.searchedUserNames == ["haru_01"])
        #expect(viewModel.searchState == .found(found(.none, user: user)))
        #expect(viewModel.resultAvatarURL == avatarURL)
    }

    @Test func searchNotFound() async {
        let fake = FakeFriendDataSource()
        let viewModel = makeViewModel(fake)
        viewModel.query = "nobody"

        await viewModel.search()

        #expect(viewModel.searchState == .notFound)
    }

    @Test func searchInvalidInputFailsWithoutRequest() async {
        let fake = FakeFriendDataSource()
        let viewModel = makeViewModel(fake)
        viewModel.query = "a-b"

        await viewModel.search()

        #expect(viewModel.searchState == .failed(UserName.formatMessage))
        #expect(fake.searchedUserNames.isEmpty)
    }

    @Test func searchFailureShowsMessage() async {
        let fake = FakeFriendDataSource()
        fake.searchResult = .failure(FakeFriendError(errorDescription: "通信エラー"))
        let viewModel = makeViewModel(fake)
        viewModel.query = "haru_01"

        await viewModel.search()

        #expect(viewModel.searchState == .failed("通信エラー"))
    }

    @Test func canSearchRequiresInput() {
        let viewModel = makeViewModel(FakeFriendDataSource())
        #expect(!viewModel.canSearch)
        viewModel.query = "   "
        #expect(!viewModel.canSearch)
        viewModel.query = "a"
        #expect(viewModel.canSearch)
    }

    // MARK: - 申請

    @Test func sendRequestMarksRequested() async {
        let fake = FakeFriendDataSource()
        let result = found(.none)
        fake.searchResult = .success(result)
        fake.sendResult = .success(.requested)
        let viewModel = makeViewModel(fake)
        viewModel.query = "haru_01"
        await viewModel.search()

        let becameFriends = await viewModel.sendRequest()

        #expect(!becameFriends)
        #expect(fake.sentUserIDs == [result.user.id])
        #expect(viewModel.searchState == .found(found(.requested, user: result.user)))
        #expect(viewModel.completionMessage == "フレンド申請を送りました。")
        #expect(!viewModel.isSending)
    }

    @Test func sendRequestToIncomingUserBecomesFriend() async {
        let fake = FakeFriendDataSource()
        let result = found(.incoming)
        fake.searchResult = .success(result)
        fake.sendResult = .success(.accepted)
        let viewModel = makeViewModel(fake)
        viewModel.query = "haru_01"
        await viewModel.search()

        let becameFriends = await viewModel.sendRequest()

        #expect(becameFriends)
        #expect(viewModel.searchState == .found(found(.friend, user: result.user)))
        #expect(viewModel.completionMessage == "はるさんとフレンドになりました。")
    }

    @Test(arguments: [FriendRelation.me, .friend, .requested])
    func sendRequestDoesNothingForOtherRelations(relation: FriendRelation) async {
        let fake = FakeFriendDataSource()
        fake.searchResult = .success(found(relation))
        let viewModel = makeViewModel(fake)
        viewModel.query = "haru_01"
        await viewModel.search()

        let becameFriends = await viewModel.sendRequest()

        #expect(!becameFriends)
        #expect(fake.sentUserIDs.isEmpty)
    }

    @Test func sendRequestAlreadyFriendsUpdatesRelation() async {
        let fake = FakeFriendDataSource()
        let result = found(.none)
        fake.searchResult = .success(result)
        fake.sendResult = .failure(FriendRepositoryError.alreadyFriends)
        let viewModel = makeViewModel(fake)
        viewModel.query = "haru_01"
        await viewModel.search()

        await viewModel.sendRequest()

        #expect(viewModel.searchState == .found(found(.friend, user: result.user)))
        #expect(viewModel.sendErrorMessage == "既にフレンドです。")
    }

    @Test func sendRequestFailureKeepsRelationAndShowsMessage() async {
        let fake = FakeFriendDataSource()
        let result = found(.none)
        fake.searchResult = .success(result)
        fake.sendResult = .failure(FakeFriendError(errorDescription: "通信エラー"))
        let viewModel = makeViewModel(fake)
        viewModel.query = "haru_01"
        await viewModel.search()

        await viewModel.sendRequest()

        #expect(viewModel.searchState == .found(result))
        #expect(viewModel.sendErrorMessage == "通信エラー")
        #expect(viewModel.completionMessage == nil)
    }
}
