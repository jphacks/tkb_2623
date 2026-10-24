//
//  GrowView.swift
//  GourmetShareMap
//

import SwiftUI

/// 育てる。登録した店舗数（= AIの学習データ数）でまんぷく先生が3段階に育つ画面。
/// 学習と推論は別リポジトリのAPIが担当するので、この画面は表示とAPI呼び出しだけを持つ。
struct GrowView: View {
    @Environment(RecordStore.self) private var recordStore
    @State private var viewModel = GrowViewModel()

    private var progress: MascotProgress {
        viewModel.progress(storeCount: recordStore.records.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(.appBorder)

            ScrollView {
                VStack(spacing: 14) {
                    heroCard
                    statTiles
                    recommendSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
        }
        .background(.appBackground)
        // 表示時と、記録を登録・更新したあとにモデルの状態を取り直す。
        .task(id: recordStore.records) { await viewModel.loadStats(records: recordStore.records) }
        .sheet(isPresented: recommendationSheetBinding) {
            if let recommendation = viewModel.recommendation {
                RecommendationSheet(recommendation: recommendation) {
                    viewModel.dismissRecommendation()
                }
            }
        }
    }

    private var header: some View {
        // 登録件数は下の「教えたお店」タイルに出るので、ここでは見出しだけ。
        Text("育てる")
            .font(.system(size: 28, weight: .heavy))
            .foregroundStyle(.appText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
    }

    private var heroCard: some View {
        VStack(spacing: 0) {
            HStack {
                levelBadge
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            MascotAnimationView(level: progress.level)
                .frame(height: 176)
                .padding(.horizontal, 20)

            LevelProgressBar(progress: progress)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0xFFF7E8), Color(hex: 0xF0E2C8)],
                        center: .top,
                        startRadius: 0,
                        endRadius: 320
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color(hex: 0x9A7846).opacity(0.16), lineWidth: 1)
                }
        }
    }

    private var levelBadge: some View {
        HStack(spacing: 7) {
            Text("\(progress.level.rawValue)")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(.appPrimary, in: Circle())

            Text(progress.level.name)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(.appText)
        }
        .padding(.leading, 5)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .background(.appCard, in: Capsule())
    }

    private var statTiles: some View {
        HStack(spacing: 10) {
            GrowStatTile(
                title: "教えたお店",
                value: "\(recordStore.records.count)",
                unit: "件",
                note: "AIの学習データ"
            )

            GrowStatTile(
                title: "好みの読み当て",
                value: accuracyValue,
                unit: viewModel.stats?.accuracyPercent == nil ? nil : "%",
                note: accuracyNote
            )
        }
    }

    private var accuracyValue: String {
        guard let percent = viewModel.stats?.accuracyPercent else { return "—" }
        return "\(percent)"
    }

    private var accuracyNote: String {
        guard let mae = viewModel.stats?.meanAbsoluteError else {
            return "APIに繋がると表示されます"
        }
        return String(format: "5段階で±%.1fのズレ", mae)
    }

    private var recommendSection: some View {
        VStack(spacing: 8) {
            Button {
                Task { await viewModel.recommend(records: recordStore.records) }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isRecommending {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 17, weight: .bold))
                    }

                    Text(viewModel.isRecommending ? "考えています…" : "今日のおすすめを聞く")
                        .font(.system(size: 16.5, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(.appPrimary, in: Capsule())
            }
            .disabled(viewModel.isRecommending || !canRecommend)
            .opacity(canRecommend ? 1 : 0.45)

            if let message = viewModel.recommendErrorMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.appPrimary)
                    .multilineTextAlignment(.center)
            } else {
                Text(recommendHint)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.appText.opacity(0.45))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 2)
    }

    /// 記録を読み込めていて、1件以上あるときだけ押せる。
    private var canRecommend: Bool {
        recordStore.loadState == .loaded && !recordStore.records.isEmpty
    }

    private var recommendHint: String {
        switch recordStore.loadState {
        case .idle, .loading:
            "記録を読み込んでいます…"
        case .failed:
            "記録を読み込めませんでした。通信状況を確認してください。"
        case .loaded:
            recordStore.records.isEmpty
                ? "お店を1件登録すると、まんぷく先生が育ちはじめます"
                : "近くのお店から、まんぷく先生が好みを予測します"
        }
    }

    private var recommendationSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel.recommendation != nil },
            set: { isPresented in
                if !isPresented { viewModel.dismissRecommendation() }
            }
        )
    }
}

#Preview {
    GrowView()
        .environment(RecordStore())
}
