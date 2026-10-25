//
//  FriendAddViewModel.swift
//  GourmetShareMap
//

import Foundation
import Observation

/// フレンド追加画面で、自分の user_name を表示するための読み込み口。テストではフェイクに差し替える。
protocol MyProfileFetching {
    func fetchMyProfile() async throws -> UserProfile
}

extension UserRepository: MyProfileFetching {}

/// フレンド追加画面。user_name の完全一致で相手を探し、関係に応じて申請する。
@Observable
final class FriendAddViewModel {
    enum SearchState: Equatable {
        case idle
        case searching
        case notFound
        case found(FriendSearchResult)
        case failed(String)
    }

    /// 自分の user_name。読み込み前・失敗時は nil。
    private(set) var myUserName: String?
    /// 検索する相手の user_name。大文字が入力されたら、その場で小文字に揃える。
    var query = "" {
        didSet {
            let lowercased = query.lowercased()
            if lowercased != query { query = lowercased }
        }
    }
    private(set) var searchState: SearchState = .idle
    /// 検索結果の相手のアイコンの署名付きURL。
    private(set) var resultAvatarURL: URL?
    private(set) var isSending = false
    /// 申請・承認が完了したときのメッセージ。
    private(set) var completionMessage: String?
    /// 申請・承認に失敗したときのメッセージ。
    private(set) var sendErrorMessage: String?

    private let repository: any FriendDataSource
    private let profileSource: any MyProfileFetching

    /// 引数を省略すると Supabase に接続する本番の Repository を使う。
    init(repository: (any FriendDataSource)? = nil, profileSource: (any MyProfileFetching)? = nil) {
        self.repository = repository ?? FriendRepository()
        self.profileSource = profileSource ?? UserRepository()
    }

    /// 検索ボタンを押せるか。
    var canSearch: Bool {
        !UserName.normalize(query).isEmpty && searchState != .searching
    }

    func loadMyUserName() async {
        // 自分の user_name が出せなくても検索・申請はできるので、失敗時は表示しないだけにする。
        myUserName = try? await profileSource.fetchMyProfile().userName
    }

    func search() async {
        completionMessage = nil
        sendErrorMessage = nil
        resultAvatarURL = nil

        let normalized = UserName.normalize(query)
        guard UserName.isValid(normalized) else {
            searchState = .failed(UserName.formatMessage)
            return
        }

        searchState = .searching
        do {
            guard let result = try await repository.searchUser(userName: normalized) else {
                searchState = .notFound
                return
            }
            searchState = .found(result)
            if let path = result.user.profileImage {
                resultAvatarURL = await repository.avatarURLs(for: [path])[path]
            }
        } catch {
            searchState = .failed(error.localizedDescription)
        }
    }

    /// 検索結果の相手に申請する。相手から申請が来ていれば、その場で承認扱いになる。
    /// フレンドが成立したら true を返す（呼び出し側で受信申請の件数を取り直す）。
    @discardableResult
    func sendRequest() async -> Bool {
        guard case .found(let result) = searchState,
              result.relation == .none || result.relation == .incoming,
              !isSending else { return false }

        isSending = true
        completionMessage = nil
        sendErrorMessage = nil
        defer { isSending = false }

        do {
            switch try await repository.sendRequest(to: result.user.id) {
            case .requested:
                searchState = .found(FriendSearchResult(user: result.user, relation: .requested))
                completionMessage = "フレンド申請を送りました。"
                return false
            case .accepted:
                searchState = .found(FriendSearchResult(user: result.user, relation: .friend))
                completionMessage = "\(result.user.displayName)さんとフレンドになりました。"
                return true
            }
        } catch FriendRepositoryError.alreadyFriends {
            // 検索後に相手が承認していた場合など。表示を実際の関係に合わせる。
            searchState = .found(FriendSearchResult(user: result.user, relation: .friend))
            sendErrorMessage = FriendRepositoryError.alreadyFriends.localizedDescription
            return false
        } catch {
            sendErrorMessage = error.localizedDescription
            return false
        }
    }
}
