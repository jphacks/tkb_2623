import Foundation
import Testing
@testable import GourmetShareMap

@MainActor
struct FriendRequestStoreTests {
    private func request(_ userName: String, profileImage: String? = nil) -> FriendRequest {
        FriendRequest(requester: makeFriendUser(userName, profileImage: profileImage), createdAt: .now)
    }

    @Test func refreshLoadsRequestsCountAndAvatars() async {
        let fake = FakeFriendDataSource()
        let avatarURL = URL(string: "https://example.com/a.jpg")!
        fake.incomingResult = .success([request("aoi", profileImage: "u/a.jpg"), request("haru")])
        fake.signedURLs = ["u/a.jpg": avatarURL]
        let store = FriendRequestStore(repository: fake)

        await store.refresh()

        #expect(store.loadState == .loaded)
        #expect(store.incomingCount == 2)
        #expect(store.avatarURLs == ["u/a.jpg": avatarURL])
    }

    @Test func refreshKeepsPreviousRequestsOnFailure() async {
        let fake = FakeFriendDataSource()
        fake.incomingResult = .success([request("aoi")])
        let store = FriendRequestStore(repository: fake)
        await store.refresh()

        fake.incomingResult = .failure(FakeFriendError(errorDescription: "通信エラー"))
        await store.refresh()

        #expect(store.loadState == .failed("通信エラー"))
        // バッジが一時的な通信失敗で消えないよう、直前の一覧を残す。
        #expect(store.incomingCount == 1)
    }

    @Test func acceptCallsRepositoryAndRefreshes() async {
        let fake = FakeFriendDataSource()
        let target = request("aoi")
        fake.incomingResult = .success([target])
        let store = FriendRequestStore(repository: fake)
        await store.refresh()

        fake.incomingResult = .success([])
        let succeeded = await store.accept(target)

        #expect(succeeded)
        #expect(fake.acceptedRequesterIDs == [target.requester.id])
        #expect(store.incomingCount == 0)
        #expect(store.actionErrorMessage == nil)
        #expect(store.processingRequesterIDs.isEmpty)
    }

    @Test func rejectCallsRepositoryAndRefreshes() async {
        let fake = FakeFriendDataSource()
        let target = request("aoi")
        fake.incomingResult = .success([target])
        let store = FriendRequestStore(repository: fake)
        await store.refresh()

        fake.incomingResult = .success([])
        let succeeded = await store.reject(target)

        #expect(succeeded)
        #expect(fake.rejectedRequesterIDs == [target.requester.id])
        #expect(store.incomingCount == 0)
    }

    @Test func acceptFailureShowsMessageAndRefreshes() async {
        let fake = FakeFriendDataSource()
        let target = request("aoi")
        fake.incomingResult = .success([target])
        fake.acceptError = FriendRepositoryError.requestNotFound
        let store = FriendRequestStore(repository: fake)
        await store.refresh()

        // 相手が申請を取り消していた想定。
        fake.incomingResult = .success([])
        let succeeded = await store.accept(target)

        #expect(!succeeded)
        #expect(store.actionErrorMessage == FriendRepositoryError.requestNotFound.localizedDescription)
        #expect(store.incomingCount == 0)
        #expect(fake.fetchIncomingCallCount == 2)
    }
}
