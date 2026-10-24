//
//  StoreSearchService.swift
//  GourmetShareMap
//

import CoreLocation

/// 位置を受け取って周辺の店舗候補を返すインターフェース（PR-05 との接点）。
///
/// - 候補が 0 件のときはエラーではなく空配列を返す。
/// - 通信失敗・API エラーなどは throw する。UI 側は `localizedDescription` をそのまま表示する。
/// - 位置の決定（EXIF 優先・なければ現在地）は呼び出し側（RecordViewModel）で行う。
protocol StoreSearchService {
    func searchNearbyStores(around coordinate: CLLocationCoordinate2D) async throws -> [StoreCandidate]
}
