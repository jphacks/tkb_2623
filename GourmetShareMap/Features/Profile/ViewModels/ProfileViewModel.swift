//
//  ProfileViewModel.swift
//  GourmetShareMap
//

import Combine
import Foundation

struct ProfileRecord: Identifiable {
    let id = UUID()
    let storeName: String
    let category: String
    let rating: Double
    let repeatCount: Int
}

/// ProfileViewModelが依存する、プロフィール取得口。テストではフェイクに差し替える。
protocol ProfileProfileDataSource {
    func fetchMyProfile() async throws -> UserProfile
    /// 任意の`userID`のプロフィールを取得する。友達のプロフィール表示用。
    func fetchProfile(userID: UUID) async throws -> UserProfile
    // プロトコル要件にデフォルト引数は書けないため、呼び出し側で明示的に指定する。
    func signedURL(path: String, expiresIn: Int) async throws -> URL
}

/// ProfileViewModelが依存する、店舗記録取得口。テストではフェイクに差し替える。
protocol ProfileStoresDataSource {
    func fetchStores() async throws -> [StoreRecord]
    /// 任意の`userID`の店舗記録を取得する。友達のプロフィール表示用。
    func fetchStores(userID: UUID) async throws -> [StoreRecord]
}

extension UserRepository: ProfileProfileDataSource {}
extension RecordRepository: ProfileStoresDataSource {}

@MainActor
final class ProfileViewModel: ObservableObject {
    /// どのユーザーのプロフィールを表示するか。`.me`はログイン中ユーザー自身、
    /// `.friend`はタイムライン等から指定した任意のユーザー（表示専用）。
    enum Target: Equatable {
        case me
        case friend(userID: UUID)
    }

    @Published private(set) var displayName: String = ""
    @Published private(set) var bio: String?
    @Published private(set) var storeCount: Int = 0
    @Published private(set) var maxRepeatCount: Int = 0
    // フレンド機能は別タスクで実装するため、DBアクセスせず常に0を返す。
    @Published private(set) var friendCount: Int = 0
    @Published private(set) var recentRecords: [ProfileRecord] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    /// アバター表示用の署名付きURL。profile_image未設定、または取得に失敗した場合はnilのままで、
    /// Viewは固定アイコン表示にフォールバックする。
    @Published private(set) var avatarURL: URL?

    /// 表示中のプロフィールが自分自身のものか。Viewが編集・ログアウトUIの表示/非表示を切り替えるために使う。
    let isOwnProfile: Bool

    private let target: Target
    private let profileDataSource: any ProfileProfileDataSource
    private let storesDataSource: any ProfileStoresDataSource

    // デフォルト引数の評価はnonisolatedなコンテキストで行われ、MainActor隔離の
    // UserRepository()/RecordRepository()を直接呼べないため、init本体でnilの場合に生成する。
    // 取得の開始はView側のタスク（ProfileView.body の.task）が呼ぶload()に委ねる。
    init(
        target: Target = .me,
        profileDataSource: (any ProfileProfileDataSource)? = nil,
        storesDataSource: (any ProfileStoresDataSource)? = nil
    ) {
        self.target = target
        self.isOwnProfile = target == .me
        self.profileDataSource = profileDataSource ?? UserRepository()
        self.storesDataSource = storesDataSource ?? RecordRepository()
    }

    /// `target`で指定したユーザーのプロフィールと店舗記録を取得し、画面表示用の値に反映する。
    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let profile = fetchProfile()
            async let stores = fetchStores()
            let (fetchedProfile, fetchedStores) = try await (profile, stores)

            // 初回ログイン時にAppleから取得した名前がuser.nameに保存されるため、
            // 通常はnilにならないが、保険として空文字にフォールバックする。
            displayName = fetchedProfile.name ?? ""
            bio = fetchedProfile.bio
            storeCount = fetchedStores.count
            maxRepeatCount = fetchedStores.map(\.repeatNum).max() ?? 0
            // fetchStores()はcreated_at降順で返るため、先頭5件がそのまま「最近の記録」になる。
            recentRecords = fetchedStores.prefix(5).map { store in
                ProfileRecord(
                    storeName: store.name,
                    category: store.category ?? "未分類",
                    rating: store.reputation ?? 0,
                    repeatCount: store.repeatNum
                )
            }

            await loadAvatarURL(path: fetchedProfile.profileImage)
        } catch {
            errorMessage = error.localizedDescription
            avatarURL = nil
        }
        isLoading = false
    }

    /// `target`に応じて、自分 or 指定したユーザーのプロフィールを取得する。
    private func fetchProfile() async throws -> UserProfile {
        switch target {
        case .me: return try await profileDataSource.fetchMyProfile()
        case .friend(let userID): return try await profileDataSource.fetchProfile(userID: userID)
        }
    }

    /// `target`に応じて、自分 or 指定したユーザーの店舗記録を取得する。
    private func fetchStores() async throws -> [StoreRecord] {
        switch target {
        case .me: return try await storesDataSource.fetchStores()
        case .friend(let userID): return try await storesDataSource.fetchStores(userID: userID)
        }
    }

    /// 保存済みのprofile_imageパスから署名付きURLを取得する。
    /// パスが無い場合、または取得に失敗した場合は、画面全体のエラーにはせずavatarURLをnilのままにする
    /// （Viewが固定アイコンにフォールバックする）。
    private func loadAvatarURL(path: String?) async {
        guard let path else {
            avatarURL = nil
            return
        }
        do {
            avatarURL = try await profileDataSource.signedURL(path: path, expiresIn: 3600)
        } catch {
            avatarURL = nil
        }
    }
}
