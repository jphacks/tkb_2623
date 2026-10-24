//
//  PhotoSourceMenu.swift
//  GourmetShareMap
//

import SwiftUI

/// 写真の取得元（カメラ／ライブラリ）を選ぶメニュー。
struct PhotoSourceMenu<Label: View>: View {
    let onSelectCamera: () -> Void
    let onSelectLibrary: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Menu {
            PhotoSourceMenuItems(onSelectCamera: onSelectCamera, onSelectLibrary: onSelectLibrary)
        } label: {
            label
        }
    }
}

/// メニュー・ダイアログ内で使う「カメラ」「写真を選択」のボタン群。
struct PhotoSourceMenuItems: View {
    let onSelectCamera: () -> Void
    let onSelectLibrary: () -> Void

    var body: some View {
        // カメラがない端末でも、カメラ画面の左下からライブラリを選べるので無効にしない。
        Button("カメラ", systemImage: "camera.fill", action: onSelectCamera)
        Button("写真を選択", systemImage: "photo.on.rectangle", action: onSelectLibrary)
    }
}

#Preview {
    PhotoSourceMenu(onSelectCamera: {}, onSelectLibrary: {}) {
        Image(systemName: "plus")
            .frame(width: 84, height: 84)
            .cardBackground()
    }
}
