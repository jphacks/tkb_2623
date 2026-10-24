//
//  StoreCandidatePicker.swift
//  GourmetShareMap
//

import CoreLocation
import SwiftUI

/// 周辺店舗の候補から 1 件を選ぶドロップダウン。読み込み中・0 件・エラーの表示も持つ。
struct StoreCandidatePicker: View {
    let state: RecordViewModel.SearchState
    let searchedCoordinate: CLLocationCoordinate2D?
    @Binding var selection: NearbyShop?
    let onRetry: () -> Void

    @State private var isExpanded = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        switch state {
        case .idle, .searching:
            messageCard {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("近くのお店を探しています…")
                        .font(.subheadline)
                        .foregroundStyle(.appText.opacity(0.7))
                }
            }
        case .loaded(let candidates) where candidates.isEmpty:
            messageCard {
                VStack(spacing: 8) {
                    Image(systemName: "mappin.slash")
                        .font(.title2)
                        .foregroundStyle(.appText.opacity(0.5))
                    Text("近くにお店が見つかりませんでした")
                        .font(.subheadline.bold())
                    Text("お店の近くで撮った写真を選ぶか、お店の近くで再検索してください")
                        .font(.caption)
                        .foregroundStyle(.appText.opacity(0.6))
                        .multilineTextAlignment(.center)
                    retryButton
                }
            }
        case .loaded(let candidates):
            dropdown(candidates)
        case .failed(let message, let isPermissionDenied):
            messageCard {
                VStack(spacing: 8) {
                    Image(systemName: isPermissionDenied ? "location.slash" : "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.appPrimary)
                    Text(message)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                    if isPermissionDenied {
                        Button("設定を開く") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(.appPrimary)
                    } else {
                        retryButton
                    }
                }
            }
        }
    }

    // MARK: - Dropdown

    private func dropdown(_ candidates: [NearbyShop]) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack {
                    if let selection {
                        candidateRow(selection)
                    } else {
                        Text("お店を選択してください")
                            .font(.subheadline)
                            .foregroundStyle(.appText.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.appText.opacity(0.6))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "候補を閉じる" : "候補を開く")

            if isExpanded {
                Divider().overlay(.appBorder)
                ForEach(candidates) { candidate in
                    Button {
                        selection = candidate
                        withAnimation(.snappy) { isExpanded = false }
                    } label: {
                        HStack {
                            candidateRow(candidate)
                            if candidate == selection {
                                Image(systemName: "checkmark")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.appPrimary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(candidate == selection ? .isSelected : [])

                    if candidate != candidates.last {
                        Divider().overlay(.appBorder).padding(.leading, 68)
                    }
                }
            }
        }
        .cardBackground()
    }

    private func candidateRow(_ candidate: NearbyShop) -> some View {
        HStack(spacing: 12) {
            Image(systemName: candidate.symbolName)
                .font(.system(size: 18))
                .foregroundStyle(.appPrimary)
                .frame(width: 44, height: 44)
                .background(.appPrimary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.name)
                    .font(.body.bold())
                    .foregroundStyle(.appText)
                    .lineLimit(1)
                Text(subtitle(for: candidate))
                    .font(.caption)
                    .foregroundStyle(.appText.opacity(0.6))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func subtitle(for candidate: NearbyShop) -> String {
        var parts = [candidate.category]
        if let searchedCoordinate {
            let meters = CLLocation(latitude: searchedCoordinate.latitude, longitude: searchedCoordinate.longitude)
                .distance(from: CLLocation(latitude: candidate.latitude, longitude: candidate.longitude))
            parts.append(Measurement(value: meters.rounded(), unit: UnitLength.meters)
                .formatted(.measurement(width: .abbreviated, usage: .road)))
        }
        return parts.joined(separator: "・")
    }

    // MARK: - Helpers

    private var retryButton: some View {
        Button("再検索", systemImage: "arrow.clockwise", action: onRetry)
            .font(.subheadline.bold())
            .foregroundStyle(.appPrimary)
    }

    private func messageCard(@ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .padding(16)
            .cardBackground()
    }
}

#Preview {
    @Previewable @State var selection: NearbyShop?
    let candidates = [
        NearbyShop(placeID: "1", name: "麺屋 はる", latitude: 35.7286, longitude: 139.7610, category: "ラーメン・麺類"),
        NearbyShop(placeID: "2", name: "中華 福来", latitude: 35.7290, longitude: 139.7615, category: "中華"),
    ]
    VStack(spacing: 16) {
        StoreCandidatePicker(
            state: .loaded(candidates),
            searchedCoordinate: CLLocationCoordinate2D(latitude: 35.7282, longitude: 139.7608),
            selection: $selection,
            onRetry: {}
        )
        StoreCandidatePicker(state: .loaded([]), searchedCoordinate: nil, selection: .constant(nil), onRetry: {})
        StoreCandidatePicker(state: .searching, searchedCoordinate: nil, selection: .constant(nil), onRetry: {})
    }
    .padding()
    .background(.appBackground)
}
