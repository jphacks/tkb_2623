//
//  TimelineFilterControl.swift
//  GourmetShareMap
//

import SwiftUI

/// 「すべて／自分／フレンド」を切り替えるカプセル型のセグメント。
struct TimelineFilterControl: View {
    @Binding var selection: TimelineFilter
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TimelineFilter.allCases) { filter in
                let isSelected = filter == selection
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = filter }
                } label: {
                    Text(filter.rawValue)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isSelected ? .white : .appText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(.appPrimary)
                                    .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.appCard, in: Capsule())
        .overlay(Capsule().strokeBorder(.appBorder, lineWidth: 1))
    }
}

#Preview {
    @Previewable @State var selection: TimelineFilter = .all
    TimelineFilterControl(selection: $selection)
        .padding()
        .background(.appBackground)
}
