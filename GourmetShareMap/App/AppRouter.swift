//
//  AppRouter.swift
//  GourmetShareMap
//

import Observation

enum AppTab: Hashable {
    case map
    case record
    case profile
}

/// 画面間のタブ移動を担う。マップの「＋」ボタンのように、
/// 別タブの画面を開かせたい操作から選択中のタブを差し替える。
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .map
}
