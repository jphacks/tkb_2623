import Foundation

/// user.user_name の入力の正規化と形式チェック。DBの check 制約（^[a-z0-9_]{3,20}$）と同じ条件にしている。
nonisolated enum UserName {
    /// 形式違反のときに表示するメッセージ。
    static let formatMessage = "ユーザー名は英小文字・数字・_（アンダースコア）の3〜20文字で入力してください。"

    /// 前後の空白を除き、大文字を小文字に揃える。
    static func normalize(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// 正規化済みの値が形式を満たすか。
    static func isValid(_ userName: String) -> Bool {
        userName.wholeMatch(of: /[a-z0-9_]{3,20}/) != nil
    }
}
