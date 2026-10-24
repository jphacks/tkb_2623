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
    /// 表紙（最初にアップロードした写真）の署名付きURL。写真が無い・取得失敗時は nil。
    var coverImageURL: URL?
}

/// ProfileViewModelが依存する、自分のプロフィール取得口。テストではフェイクに差し替える。
protocol ProfileProfileDataSource {
    func fetchMyProfile() async throws -> UserProfile
    // プロトコル要件にデフォルト引数は書けないため、呼び出し側で明示的に指定する。
    func signedURL(path: String, expiresIn: Int) async throws -> URL
}

/// ProfileViewModelが依存する、自分の店舗記録取得口。テストではフェイクに差し替える。
protocol ProfileStoresDataSource {
    func fetchStores() async throws -> [StoreRecord]
}

/// ProfileViewModelが依存する、店舗の表紙写真URL取得口。テストではフェイクに差し替える。
protocol ProfileCoverImagesDataSource {
    func coverImageURLs(storeIDs: [UUID], expiresIn: Int) async throws -> [UUID: URL]
}

extension UserRepository: ProfileProfileDataSource {}
extension RecordRepository: ProfileStoresDataSource {}
extension ImageRepository: ProfileCoverImagesDataSource {}

@MainActor
final class ProfileViewModel: ObservableObject {
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

    private let profileDataSource: any ProfileProfileDataSource
    private let storesDataSource: any ProfileStoresDataSource
    private let coverImagesDataSource: any ProfileCoverImagesDataSource

    // デフォルト引数の評価はnonisolatedなコンテキストで行われ、MainActor隔離の
    // UserRepository()/RecordRepository()/ImageRepository()を直接呼べないため、init本体でnilの場合に生成する。
    // 取得の開始はView側のタスク（ProfileView.body の.task）が呼ぶload()に委ねる。
    init(
        profileDataSource: (any ProfileProfileDataSource)? = nil,
        storesDataSource: (any ProfileStoresDataSource)? = nil,
        coverImagesDataSource: (any ProfileCoverImagesDataSource)? = nil
    ) {
        self.profileDataSource = profileDataSource ?? UserRepository()
        self.storesDataSource = storesDataSource ?? RecordRepository()
        self.coverImagesDataSource = coverImagesDataSource ?? ImageRepository()
    }

    /// 自分のプロフィールと店舗記録を取得し、画面表示用の値に反映する。
    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let profile = profileDataSource.fetchMyProfile()
            async let stores = storesDataSource.fetchStores()
            let (fetchedProfile, fetchedStores) = try await (profile, stores)

            // 初回ログイン時にAppleから取得した名前がuser.nameに保存されるため、
            // 通常はnilにならないが、保険として空文字にフォールバックする。
            displayName = fetchedProfile.name ?? ""
            bio = fetchedProfile.bio
            storeCount = fetchedStores.count
            maxRepeatCount = fetchedStores.map(\.repeatNum).max() ?? 0
            // fetchStores()はcreated_at降順で返るため、先頭5件がそのまま「最近の記録」になる。
            let recentStores = Array(fetchedStores.prefix(5))
            let coverURLs = await loadCoverImageURLs(storeIDs: recentStores.map(\.id))
            recentRecords = recentStores.map { store in
                ProfileRecord(
                    storeName: store.name,
                    category: store.category ?? "未分類",
                    rating: store.reputation ?? 0,
                    repeatCount: store.repeatNum,
                    coverImageURL: coverURLs[store.id]
                )
            }

            await loadAvatarURL(path: fetchedProfile.profileImage)
        } catch {
            errorMessage = error.localizedDescription
            avatarURL = nil
        }
        isLoading = false
    }

    /// 最近の記録の表紙写真URL。取得に失敗しても画面全体のエラーにはせず、
    /// 各行は固定アイコンにフォールバックする。
    private func loadCoverImageURLs(storeIDs: [UUID]) async -> [UUID: URL] {
        do {
            return try await coverImagesDataSource.coverImageURLs(storeIDs: storeIDs, expiresIn: 3600)
        } catch {
            return [:]
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
