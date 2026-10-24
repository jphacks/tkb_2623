//
//  ProfileEditViewModel.swift
//  GourmetShareMap
//

import Combine
import Foundation

/// ProfileEditViewModelが依存する、自分のプロフィール読み込み・更新口。テストではフェイクに差し替える。
protocol ProfileEditDataSource {
    func fetchMyProfile() async throws -> UserProfile
    func updateMyProfile(name: String?, bio: String?, userName: String?) async throws
    func uploadProfileImage(data: Data, format: RecordImageFormat) async throws -> String
    // プロトコル要件にデフォルト引数は書けないため、呼び出し側で明示的に指定する。
    func signedURL(path: String, expiresIn: Int) async throws -> URL
}

extension UserRepository: ProfileEditDataSource {}

@MainActor
final class ProfileEditViewModel: ObservableObject {
    @Published var name: String = ""
    /// フレンド検索に使うユーザー名。大文字が入力されたら、その場で小文字に揃える。
    @Published var userName: String = "" {
        didSet {
            let lowercased = userName.lowercased()
            if lowercased != userName { userName = lowercased }
        }
    }
    @Published var bio: String = ""
    /// 保存済みの画像の表示用URL。新しい画像を選択しただけではここは更新されない
    /// （プレビューはpendingImageDataをViewがそのまま表示する想定）。
    @Published private(set) var avatarPreviewURL: URL?
    /// 選択済みだが未保存の画像データ。save()が呼ばれるまでアップロードしない。
    @Published private(set) var pendingImageData: Data?
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?
    @Published private(set) var didSaveSuccessfully = false

    private let dataSource: any ProfileEditDataSource
    private var pendingImageFormat: RecordImageFormat = .jpeg

    // デフォルト引数の評価はnonisolatedなコンテキストで行われ、MainActor隔離の
    // UserRepository()を直接呼べないため、init本体でnilの場合に生成する。
    // 読み込みの開始はView側のタスクが呼ぶload()に委ねる。
    init(dataSource: (any ProfileEditDataSource)? = nil) {
        self.dataSource = dataSource ?? UserRepository()
    }

    /// 現在のプロフィール（ユーザー名・表示名・自己紹介・画像プレビュー）を読み込む。
    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let profile = try await dataSource.fetchMyProfile()
            name = profile.name ?? ""
            userName = profile.userName ?? ""
            bio = profile.bio ?? ""
            await loadAvatarPreviewURL(path: profile.profileImage)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// 新しい画像を選択する。保存するまでアップロードは行わない。
    func selectImage(data: Data, format: RecordImageFormat = .jpeg) {
        pendingImageData = data
        pendingImageFormat = format
    }

    /// 選択済みの未保存画像を取り消す。
    func cancelPendingImage() {
        pendingImageData = nil
    }

    /// 表示名・自己紹介・ユーザー名を更新し、画像を選択していればアップロードして反映する。
    /// ユーザー名が形式を満たさない場合は、通信せずにエラーを表示する。
    /// uploadProfileImage(data:format:)は内部でuser.profile_imageの更新まで行うため、
    /// ここで別途updateMyProfileImageを呼ぶと二重更新になる（このViewModelはそのメソッドに
    /// 依存していないため、呼び出しようがない構成にしている）。
    func save() async {
        errorMessage = nil
        didSaveSuccessfully = false

        let normalizedUserName = UserName.normalize(userName)
        guard UserName.isValid(normalizedUserName) else {
            errorMessage = UserName.formatMessage
            return
        }

        isSaving = true
        do {
            try await dataSource.updateMyProfile(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                bio: bio.trimmingCharacters(in: .whitespacesAndNewlines),
                userName: normalizedUserName
            )
            userName = normalizedUserName

            if let pendingImageData {
                let newPath = try await dataSource.uploadProfileImage(data: pendingImageData, format: pendingImageFormat)
                self.pendingImageData = nil
                await loadAvatarPreviewURL(path: newPath)
            }

            didSaveSuccessfully = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    /// 保存済みの画像パスから表示用の署名付きURLを取得する。
    /// パスが無い場合、または取得に失敗した場合は、呼び出し元の処理全体のエラーにはせず
    /// avatarPreviewURLをnilのままにする。
    private func loadAvatarPreviewURL(path: String?) async {
        guard let path else {
            avatarPreviewURL = nil
            return
        }
        do {
            avatarPreviewURL = try await dataSource.signedURL(path: path, expiresIn: 3600)
        } catch {
            avatarPreviewURL = nil
        }
    }
}
