//
//  NonceUtils.swift
//  GourmetShareMap
//

import CryptoKit
import Foundation

enum NonceUtils {
    // Sign in with AppleのリプレイAttack対策用nonce。生成した生の文字列はApple側のrequestにはSHA256ハッシュで渡し、
    // 生の文字列はSupabaseのsignInWithIdTokenに渡してサーバー側で突き合わせてもらう。
    static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if status != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(status)")
        }

        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { byte in charset[Int(byte) % charset.count] })
    }

    static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}
