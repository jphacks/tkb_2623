//
//  CategoryFilterChip.swift
//  GourmetShareMap

import SwiftUI

struct CategoryFilterChip: View {
    let category: MapCategoryFilter
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if category != .all {
                    Image(systemName: category.symbolName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
                Text(category.rawValue)
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(isSelected ? Color.white : Color.black.opacity(0.75))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.black : Color.white, in: Capsule())
            .overlay {
                if !isSelected {
                    Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var iconColor: Color {
        switch category {
        case .ramen: Color(red: 0.86, green: 0.42, blue: 0.24)
        case .chinese: Color(red: 0.80, green: 0.60, blue: 0.20)
        case .western: Color(red: 0.33, green: 0.52, blue: 0.80)
        case .cafe: Color(red: 0.56, green: 0.43, blue: 0.31)
        case .all: Color.clear
        }
    }
}

#Preview {
    HStack {
        CategoryFilterChip(category: .all, isSelected: true) {}
        CategoryFilterChip(category: .ramen, isSelected: false) {}
        CategoryFilterChip(category: .cafe, isSelected: false) {}
    }
    .padding()
}
