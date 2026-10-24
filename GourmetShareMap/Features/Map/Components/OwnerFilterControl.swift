//
//  OwnerFilterControl.swift
//  GourmetShareMap

import SwiftUI

struct OwnerFilterControl: View {
    @Binding var selection: OwnerFilter

    private let accentOrange = Color(red: 0.76, green: 0.35, blue: 0.22)

    var body: some View {
        HStack(spacing: 8) {
            ForEach(OwnerFilter.allCases) { filter in
                Button {
                    selection = filter
                } label: {
                    Text(filter.rawValue)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(selection == filter ? Color.white : Color.black.opacity(0.75))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(selection == filter ? accentOrange : Color.white, in: Capsule())
                        .overlay {
                            if selection != filter {
                                Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    OwnerFilterControl(selection: .constant(.both))
        .padding()
}
