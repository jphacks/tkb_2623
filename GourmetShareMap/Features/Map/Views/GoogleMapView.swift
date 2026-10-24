//
//  GoogleMapView.swift
//  GourmetShareMap
//

import CoreLocation
import GoogleMaps
import SwiftUI

/// カメラ移動の指示。
///
/// 一度適用した指示を再適用するとユーザーの地図操作を奪ってしまうため、`id` で適用済みかを判定する。
/// 座標の値比較に頼らないのは `CLLocationCoordinate2D` が `Equatable` ではないため。
struct MapCameraRequest: Identifiable, Equatable {
    let id: UUID
    /// 1件なら中心に寄せ、複数なら全件が入るようにフィットさせる。
    let coordinates: [CLLocationCoordinate2D]
    let zoom: Float

    private init(coordinates: [CLLocationCoordinate2D], zoom: Float) {
        self.id = UUID()
        self.coordinates = coordinates
        self.zoom = zoom
    }

    static func center(_ coordinate: CLLocationCoordinate2D, zoom: Float = 15) -> MapCameraRequest {
        MapCameraRequest(coordinates: [coordinate], zoom: zoom)
    }

    static func fit(_ coordinates: [CLLocationCoordinate2D]) -> MapCameraRequest {
        MapCameraRequest(coordinates: coordinates, zoom: 15)
    }

    static func == (lhs: MapCameraRequest, rhs: MapCameraRequest) -> Bool {
        lhs.id == rhs.id
    }
}

/// `GMSMapView` のSwiftUIラッパー。
///
/// Maps SDK for iOSはUIKitベースでSwiftUIビューを提供していないため、公式ドキュメントの案内どおり
/// `UIViewRepresentable` でラップする。公式サンプルはdelegateを`static`で共有しているが、
/// 複数インスタンスで取り違える上に共有可変状態になるため、`Coordinator`に持たせる。
struct GoogleMapView: UIViewRepresentable {
    let stores: [MapStore]
    /// 店舗ごとのピン写真。読み込みが終わった分だけ順次渡ってくる。
    let photos: [MapStore.ID: UIImage]
    let selectedStoreID: MapStore.ID?
    let cameraRequest: MapCameraRequest?
    let showsMyLocation: Bool
    /// 下部カードやフィルタに「現在地」ボタンや著作権表記が隠れないようにする余白。
    let contentInset: EdgeInsets
    let onStoreTapped: (MapStore.ID) -> Void
    let onMapTapped: () -> Void

    /// 店舗も現在地もまだ無いときの初期表示位置(谷中・根津周辺)。
    private static let fallbackCamera = GMSCameraPosition(
        latitude: 35.7205, longitude: 139.7658, zoom: 14
    )

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        options.camera = Self.fallbackCamera
        let mapView = GMSMapView(options: options)
        mapView.delegate = context.coordinator
        mapView.settings.myLocationButton = true
        mapView.settings.compassButton = true
        mapView.settings.rotateGestures = false
        mapView.settings.tiltGestures = false
        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onStoreTapped = onStoreTapped
        coordinator.onMapTapped = onMapTapped

        mapView.isMyLocationEnabled = showsMyLocation
        mapView.padding = UIEdgeInsets(
            top: contentInset.top,
            left: contentInset.leading,
            bottom: contentInset.bottom,
            right: contentInset.trailing
        )

        coordinator.sync(stores: stores, photos: photos, selectedStoreID: selectedStoreID, on: mapView)
        coordinator.apply(cameraRequest: cameraRequest, to: mapView)
    }

    @MainActor
    final class Coordinator: NSObject, GMSMapViewDelegate {
        /// ピン画像のキャッシュキー。同じ見た目のピンを描き直さないためのもの。
        private struct IconKey: Hashable {
            let category: String
            let isMine: Bool
            let sharedWithFriend: Bool
            let isSelected: Bool
            /// 写真付きのピンは店舗ごとに絵が違うため、キャッシュのキーを店舗で分ける。
            /// 写真が無い場合はnilにして、同じカテゴリのピンで1枚を使い回す。
            let photoStoreID: MapStore.ID?
        }

        var onStoreTapped: ((MapStore.ID) -> Void)?
        var onMapTapped: (() -> Void)?

        private var markers: [MapStore.ID: GMSMarker] = [:]
        private var appliedIconKeys: [MapStore.ID: IconKey] = [:]
        private var appliedCameraRequestID: UUID?
        private var iconCache: [IconKey: UIImage] = [:]

        /// 差分だけを反映する。毎回 `mapView.clear()` すると、変化していないピンも
        /// 作り直すことになり、ピン画像の再描画コストがかかる。
        func sync(
            stores: [MapStore],
            photos: [MapStore.ID: UIImage],
            selectedStoreID: MapStore.ID?,
            on mapView: GMSMapView
        ) {
            let visibleIDs = Set(stores.map(\.id))
            for (id, marker) in markers where !visibleIDs.contains(id) {
                marker.map = nil
                markers[id] = nil
                appliedIconKeys[id] = nil
            }

            for store in stores {
                let isSelected = store.id == selectedStoreID
                let marker = markers[store.id] ?? makeMarker(for: store, on: mapView)
                marker.position = store.coordinate
                // 選択中のピンは隣のピンの下に隠れないように前面へ出す。
                marker.zIndex = isSelected ? 1 : 0

                let photo = photos[store.id]
                let key = IconKey(
                    category: store.category,
                    isMine: store.isMine,
                    sharedWithFriend: store.sharedWithFriend,
                    isSelected: isSelected,
                    photoStoreID: photo == nil ? nil : store.id
                )
                if appliedIconKeys[store.id] != key {
                    marker.icon = icon(
                        for: key,
                        photo: photo,
                        scale: mapView.traitCollection.displayScale
                    )
                    appliedIconKeys[store.id] = key
                }
            }
        }

        func apply(cameraRequest: MapCameraRequest?, to mapView: GMSMapView) {
            guard let cameraRequest, cameraRequest.id != appliedCameraRequestID else { return }
            appliedCameraRequestID = cameraRequest.id

            if cameraRequest.coordinates.count == 1, let coordinate = cameraRequest.coordinates.first {
                mapView.animate(toLocation: coordinate)
                mapView.animate(toZoom: cameraRequest.zoom)
                return
            }
            guard var bounds = cameraRequest.coordinates.first.map(
                { GMSCoordinateBounds(coordinate: $0, coordinate: $0) }
            ) else { return }
            for coordinate in cameraRequest.coordinates.dropFirst() {
                bounds = bounds.includingCoordinate(coordinate)
            }
            mapView.animate(with: GMSCameraUpdate.fit(bounds, withPadding: 48))
        }

        private func makeMarker(for store: MapStore, on mapView: GMSMapView) -> GMSMarker {
            let marker = GMSMarker(position: store.coordinate)
            // ピンの下端の尖りが店舗の位置を指すようにする。
            marker.groundAnchor = CGPoint(x: 0.5, y: 1)
            marker.userData = store.id
            marker.map = mapView
            markers[store.id] = marker
            return marker
        }

        /// SwiftUIで定義したピンを`GMSMarker.icon`に渡せるようビットマップ化する。
        private func icon(for key: IconKey, photo: UIImage?, scale: CGFloat) -> UIImage? {
            if let cached = iconCache[key] { return cached }
            let renderer = ImageRenderer(
                content: ShopPinView(
                    category: key.category,
                    isMine: key.isMine,
                    sharedWithFriend: key.sharedWithFriend,
                    isSelected: key.isSelected,
                    photo: photo
                )
            )
            renderer.scale = scale
            guard let image = renderer.uiImage else { return nil }
            iconCache[key] = image
            return image
        }

        // MARK: - GMSMapViewDelegate

        // SDKはメインスレッドからのみコールバックするが、delegateの宣言には分離指定がないため
        // nonisolatedな要件として実装し、assumeIsolatedでメインアクターに合流する。
        nonisolated func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            MainActor.assumeIsolated {
                guard let id = marker.userData as? MapStore.ID else { return false }
                onStoreTapped?(id)
                // trueを返して既定の吹き出し表示とカメラ移動を抑止し、下部カードに任せる。
                return true
            }
        }

        nonisolated func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            MainActor.assumeIsolated {
                onMapTapped?()
            }
        }
    }
}
