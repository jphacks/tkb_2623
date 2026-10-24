//
//  ProfileStatColumn.swift
//  GourmetShareMap

import SwiftUI

struct ProfileStatColumn: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.black)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.black.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    HStack {
        ProfileStatColumn(value: "24", label: "登録店舗")
        ProfileStatColumn(value: "8回", label: "最大リピート")
        ProfileStatColumn(value: "12", label: "フレンド")
    }
    .padding()
}
