//
//  CategoryFilterMenu.swift
//  GourmetShareMap

import SwiftUI

/// カテゴリの絞り込み。現在の選択をそのまま表示するポップアップボタン。
///
/// 13分類＋「すべて」を横スクロールのチップで並べると、地図の縦幅を常に奪い、
/// 地図自身のパン操作と競合し、Dynamic Type拡大時に長いカテゴリ名が破綻する。
/// HIGがこの条件(相互排他・項目数が多い・スペースが限られる)に挙げているのは
/// ポップアップボタンで、SwiftUIも5個を超える選択肢にはメニュー形式を推奨している。
struct CategoryFilterMenu: View {
    @Binding var selection: StoreCategoryFilter

    private let accentOrange = Color(red: 0.76, green: 0.35, blue: 0.22)

    var body: some View {
        Menu {
            // .inlineにしないとPickerが入れ子のサブメニューとして表示される。
            // インライン展開するとシステムのチェックマーク付き一覧になる。
            Picker("カテゴリ", selection: $selection) {
                ForEach(StoreCategoryFilter.allFilters) { filter in
                    Label(filter.title, systemImage: filter.symbolName)
                        .tag(filter)
                }
            }
            .pickerStyle(.inline)

            if selection.isActive {
                Section {
                    Button("絞り込みを解除", systemImage: "xmark") {
                        selection = .all
                    }
                }
            }
        } label: {
            label
        }
        // 「すべて」を先頭に固定する。既定では使用頻度で並び替えられる。
        .menuOrder(.fixed)
        .accessibilityLabel("カテゴリで絞り込み")
        .accessibilityValue(selection.title)
    }

    private var label: some View {
        HStack(spacing: 6) {
            Image(systemName: selection.symbolName)
                .font(.system(size: 13, weight: .semibold))
            Text(selection.title)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .opacity(0.6)
        }
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(selection.isActive ? Color.white : Color.black.opacity(0.75))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(selection.isActive ? accentOrange : Color.white, in: Capsule())
        .overlay {
            if !selection.isActive {
                Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1)
            }
        }
        // 色だけに頼らず、ラベル自体が現在の絞り込みを示す。
        .contentShape(.capsule)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        CategoryFilterMenu(selection: .constant(.all))
        CategoryFilterMenu(selection: .constant(.category("ラーメン・麺類")))
        CategoryFilterMenu(selection: .constant(.category("ファストフード・食堂")))
    }
    .padding()
    .background(Color(red: 0.984, green: 0.968, blue: 0.937))
}
