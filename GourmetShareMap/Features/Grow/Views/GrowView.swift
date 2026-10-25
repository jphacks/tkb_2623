//
//  GrowView.swift
//  GourmetShareMap
//

import SwiftUI

/// 育てる。登録した店舗数（= AIの学習データ数）で相棒が3段階に育つ画面。
/// どのキャラが出るかは一番多く登録しているカテゴリで決まる（`MascotCharacterMapping`）。
/// 学習と推論はCloud Run上のAIバックエンドが担当し、この画面はSupabase Edge Function経由で呼び出すだけ。
struct GrowView: View {
    @Environment(RecordStore.self) private var recordStore
    @State private var viewModel = GrowViewModel()
    @State private var freeText = ""
    @State private var showsEmptyTextError = false
    @FocusState private var isFreeTextFocused: Bool

    private var progress: MascotProgress {
        viewModel.progress(storeCount: recordStore.records.count)
    }

    /// 一番多く登録しているカテゴリ×今のレベルで決まるキャラ。
    private var character: MascotCharacter {
        MascotCharacterMapping.character(records: recordStore.records, level: progress.level)
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
            // Appleのガイダンス: `.interactively`はTextEditor等の専用編集画面向け。
            // この画面は情報ページの中に入力欄が1つあるだけなので`.immediate`が適切。
            .scrollDismissesKeyboard(.immediately)
        }
        .background(.appBackground)
        // 表示時と、記録を登録・更新したあとにモデルの状態を取り直す。
        .task(id: recordStore.records) { await viewModel.loadStats(records: recordStore.records) }
        .sheet(isPresented: recommendationSheetBinding) {
            RecommendationSheet(recommendations: viewModel.recommendations)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("閉じる") { isFreeTextFocused = false }
                    .font(.system(size: 15, weight: .bold))
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

            MascotAnimationView(character: character, level: progress.level)
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

            Text(character.displayName)
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
        VStack(spacing: 10) {
            if progress.level == .lv1 {
                // Lv.1（登録0〜4件）はAIがまだ学習できないため、レコメンドUI自体を出さない。
                Text(progress.progressText + "、AIがレコメンドできるようになります")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.appText.opacity(0.55))
                    .multilineTextAlignment(.center)
            } else {
                Text("どんなお店に行きたい?")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.appText.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextField(
                    "", text: $freeText, prompt: Text("例: 渋谷で静かなデート向けの和食").foregroundStyle(.appText.opacity(0.35)),
                    axis: .vertical
                )
                .font(.system(size: 14.5))
                .foregroundStyle(.appText)
                .tint(.appPrimary)
                .focused($isFreeTextFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(.appCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isFreeTextFocused ? Color.appPrimary.opacity(0.6) : .appBorder, lineWidth: 1.5)
                }
                .submitLabel(.search)
                .onSubmit { requestRecommend() }
                .onChange(of: freeText) { showsEmptyTextError = false }

                Button {
                    requestRecommend()
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isRecommending {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 17, weight: .bold))
                        }

                        Text(viewModel.isRecommending ? "考えています…" : "レコメンドしてもらう")
                            .font(.system(size: 16.5, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(.appPrimary, in: Capsule())
                }
                .disabled(viewModel.isRecommending || !canRecommend)
                .opacity(canRecommend ? 1 : 0.45)

                if showsEmptyTextError {
                    Text("行きたい気分や食べたいものを入力してください")
                        .font(.system(size: 12))
                        .foregroundStyle(.appPrimary)
                        .multilineTextAlignment(.center)
                } else if let message = viewModel.recommendErrorMessage {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.appPrimary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("近くのお店から、まんぷく先生が好みを予測します")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.appText.opacity(0.45))
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.top, 2)
    }

    private func requestRecommend() {
        let text = freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            showsEmptyTextError = true
            return
        }
        showsEmptyTextError = false
        isFreeTextFocused = false
        Task { await viewModel.recommend(freeText: text, records: recordStore.records) }
    }

    /// 記録を読み込めていて、レコメンドが解禁されるLv.2以上のときだけ押せる。
    private var canRecommend: Bool {
        recordStore.loadState == .loaded && progress.level != .lv1
    }

    private var recommendationSheetBinding: Binding<Bool> {
        Binding(
            get: { !viewModel.recommendations.isEmpty },
            set: { isPresented in
                if !isPresented { viewModel.dismissRecommendations() }
            }
        )
    }
}

#Preview {
    GrowView()
        .environment(RecordStore())
}
