//
//  MapView.swift
//  GourmetShareMap
//

import SwiftUI

struct MapView: View {
    @State private var viewModel = MapViewModel()
    @State private var locationService = CurrentLocationService()
    @State private var photoLoader = StorePhotoLoader()
    @State private var cameraRequest: MapCameraRequest?
    /// 初期表示のカメラ合わせを一度だけ行うためのフラグ。以降はユーザーの操作に任せる。
    @State private var hasSetInitialCamera = false
    @State private var editingStore: MapStore?

    /// 「＋」ボタンから登録画面へ移るためのタブ切り替え。
    /// タイムライン画面と同じく、タブの選択は`MainTabView`に任せる。
    let onCreateRecord: () -> Void

    @Environment(RecordStore.self) private var recordStore

    private let backgroundColor = Color(red: 0.984, green: 0.968, blue: 0.937)
    private let accentOrange = Color(red: 0.76, green: 0.35, blue: 0.22)

    /// 店舗データは`RecordStore`が一元管理する。登録画面で保存されると
    /// そのキャッシュが更新され、こちらにもそのまま反映される。
    private var stores: [MapStore] {
        viewModel.stores(from: recordStore.visibleStores)
    }

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                header
                CategoryFilterMenu(selection: $viewModel.selectedCategory)
                ownerFilterRow
                mapCanvas
                if let store = viewModel.selectedStore(in: stores) {
                    SelectedShopCard(store: store) { editingStore = store }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .task {
            await recordStore.loadVisible()
        }
        .task {
            // 画面を離れると.taskがキャンセルされ、それが位置情報の停止処理になる。
            await locationService.startUpdates()
        }
        .onChange(of: locationService.status) { _, status in
            guard status == .streaming, let coordinate = locationService.coordinate else { return }
            // 現在地が取れたらそこを優先する。1件目の測位で一度だけ寄せる。
            guard !hasSetInitialCamera else { return }
            hasSetInitialCamera = true
            cameraRequest = .center(coordinate)
        }
        .onChange(of: stores) { _, stores in
            Task { await photoLoader.load(storeIDs: stores.map(\.id)) }

            // 表示対象から外れたピンの選択が残らないようにする。
            if let selectedStoreID = viewModel.selectedStoreID,
               !stores.contains(where: { $0.id == selectedStoreID }) {
                viewModel.select(storeID: nil)
            }

            guard !hasSetInitialCamera, !stores.isEmpty else { return }
            // 現在地がまだ無い場合は、登録済みの店舗が全部入る範囲に合わせる。
            hasSetInitialCamera = true
            cameraRequest = .fit(stores.map(\.coordinate))
        }
        .sheet(item: $editingStore) { store in
            RecordEditView(store: store) {
                Task { await recordStore.loadVisible() }
            }
        }
    }

    private var header: some View {
        Text("マップ")
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(.black)
            .padding(.top, 8)
    }

    private var ownerFilterRow: some View {
        HStack(alignment: .center) {
            OwnerFilterControl(selection: $viewModel.ownerFilter)
            Spacer()
            MapLegendView()
        }
    }

    private var mapCanvas: some View {
        ZStack {
            GoogleMapView(
                stores: viewModel.filtered(stores),
                photos: photoLoader.photos,
                selectedStoreID: viewModel.selectedStoreID,
                cameraRequest: cameraRequest,
                showsMyLocation: locationService.status == .streaming,
                // 角丸で「現在地」ボタンやGoogleの表記が切れないように内側へ寄せる。
                contentInset: EdgeInsets(top: 0, leading: 8, bottom: 8, trailing: 8),
                onStoreTapped: { viewModel.select(storeID: $0) },
                onMapTapped: { viewModel.select(storeID: nil) }
            )

            addStoreButton
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 16)
                .padding(.bottom, 76)

            statusOverlay
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var addStoreButton: some View {
        Button {
            // 下部タブの「登録」を押したときと同じ画面へ移動する。
            onCreateRecord()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(accentOrange, in: Circle())
                .shadow(color: accentOrange.opacity(0.4), radius: 8, y: 4)
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch recordStore.visibleLoadState {
        case .loading:
            ProgressView()
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case let .failed(message):
            banner(text: message, systemImage: "exclamationmark.triangle.fill") {
                Button("再試行") {
                    Task { await recordStore.loadVisible() }
                }
                .font(.system(size: 13, weight: .bold))
            }
        case .loaded where stores.isEmpty:
            banner(text: "まだ店舗が登録されていません。", systemImage: "mappin.slash")
        case .loaded, .idle:
            if locationService.status == .denied {
                banner(text: "位置情報が許可されていないため、現在地を表示できません。", systemImage: "location.slash.fill") {
                    // 一度拒否されると再度ダイアログは出ないため、設定アプリへ誘導する。
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link("設定を開く", destination: url)
                            .font(.system(size: 13, weight: .bold))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func banner(
        text: String,
        systemImage: String,
        @ViewBuilder trailing: () -> some View = { EmptyView() }
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(accentOrange)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.black.opacity(0.75))
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 12)
    }
}

#Preview {
    MapView(onCreateRecord: {})
        .environment(RecordStore())
}
