//
//  LocationService.swift
//  GourmetShareMap
//

import CoreLocation

enum LocationServiceError: LocalizedError {
    case denied
    case unavailable
    case timeout

    var errorDescription: String? {
        switch self {
        case .denied: "位置情報の利用が許可されていません。設定アプリから許可してください。"
        case .unavailable: "現在地を取得できませんでした。"
        case .timeout: "現在地の取得に時間がかかっています。電波の良い場所で再度お試しください。"
        }
    }
}

/// Core Location で現在地を 1 回だけ取得する。
/// iOS 18 以降の推奨 API（CLServiceSession + CLLocationUpdate.liveUpdates）を使う。
final class LocationService {
    func currentCoordinate(timeout: Duration = .seconds(15)) async throws -> CLLocationCoordinate2D {
        try await withThrowingTaskGroup(of: CLLocationCoordinate2D.self) { group in
            group.addTask { try await Self.firstCoordinate() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw LocationServiceError.timeout
            }
            defer { group.cancelAll() }
            guard let coordinate = try await group.next() else { throw LocationServiceError.unavailable }
            return coordinate
        }
    }

    private static func firstCoordinate() async throws -> CLLocationCoordinate2D {
        // セッションを保持している間、位置情報の利用許可ダイアログの表示と更新の受信が行われる。
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }

        for try await update in CLLocationUpdate.liveUpdates() {
            if let location = update.location {
                return location.coordinate
            }
            if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                throw LocationServiceError.denied
            }
        }
        throw LocationServiceError.unavailable
    }
}
