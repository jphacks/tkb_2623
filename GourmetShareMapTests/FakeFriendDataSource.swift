import Foundation
@testable import GourmetShareMap

/// フレンド関連の ViewModel・Store のテスト用に、FriendDataSource を差し替えるフェイク。
@MainActor
final class FakeFriendDataSource: FriendDataSource {
    var friendsResult: Result<[FriendUser], any Error> = .success([])
    var incomingResult: Result<[FriendRequest], any Error> = .success([])
    var searchResult: Result<FriendSearchResult?, any Error> = .success(nil)
    var sendResult: Result<FriendRequestSendResult, any Error> = .success(.requested)
    var acceptError: (any Error)?
    var rejectError: (any Error)?
    var signedURLs: [String: URL] = [:]

    private(set) var searchedUserNames: [String] = []
    private(set) var sentUserIDs: [UUID] = []
    private(set) var acceptedRequesterIDs: [UUID] = []
    private(set) var rejectedRequesterIDs: [UUID] = []
    private(set) var fetchIncomingCallCount = 0
    private(set) var fetchFriendsCallCount = 0

    func fetchFriends() async throws -> [FriendUser] {
        fetchFriendsCallCount += 1
        return try friendsResult.get()
    }

    func fetchIncomingRequests() async throws -> [FriendRequest] {
        fetchIncomingCallCount += 1
        return try incomingResult.get()
    }

    func searchUser(userName: String) async throws -> FriendSearchResult? {
        searchedUserNames.append(userName)
        return try searchResult.get()
    }

    func sendRequest(to userID: UUID) async throws -> FriendRequestSendResult {
        sentUserIDs.append(userID)
        return try sendResult.get()
    }

    func acceptRequest(from requesterID: UUID) async throws {
        acceptedRequesterIDs.append(requesterID)
        if let acceptError { throw acceptError }
    }

    func rejectRequest(from requesterID: UUID) async throws {
        rejectedRequesterIDs.append(requesterID)
        if let rejectError { throw rejectError }
    }

    func avatarURLs(for paths: [String]) async -> [String: URL] {
        signedURLs.filter { paths.contains($0.key) }
    }
}

struct FakeFriendError: LocalizedError {
    let errorDescription: String?
}

func makeFriendUser(_ userName: String, name: String? = nil, profileImage: String? = nil) -> FriendUser {
    FriendUser(id: UUID(), userName: userName, name: name, profileImage: profileImage)
}
