//
//  MascotCharacter.swift
//  GourmetShareMap
//

import Foundation

/// 育てる画面に出すキャラクター。Notion「AIキャラクター」仕様の8体。
/// 各キャラは `{rawValue}_01`〜`{rawValue}_08` の8枚コマ送りでAssetに入っている（レベル共通のアイドルアニメ）。
enum MascotCharacter: String, CaseIterable, Identifiable, Sendable {
    case mogumaru, kometaro, sushitaro, ramenman, sakejiro, pizaro, mugiro, cakechan

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mogumaru: "もぐまる"
        case .kometaro: "コメ太郎"
        case .sushitaro: "スシ太郎"
        case .ramenman: "ラーメンマン"
        case .sakejiro: "サケ次郎"
        case .pizaro: "ピザ郎"
        case .mugiro: "ムギ郎"
        case .cakechan: "ケーキちゃん"
        }
    }

    /// Assetに入っているコマ送り画像の名前。8枚固定（`[Image]`の仕様通り）。
    var frameImageNames: [String] {
        (1...Self.frameCount).map { String(format: "%@_%02d", rawValue, $0) }
    }

    static let frameCount = 8
}
