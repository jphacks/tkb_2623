import CoreLocation
import Observation

/// マップ画面で前景利用する現在地サービス。
///
/// 登録画面が使う `LocationService` とは役割が違う。あちらは「いまの座標を1回取って返す」もので、
/// こちらは測位を流し続け、座標と**許可の状態**を画面へ公開する。マップは現在地の青点を
/// 出し続け、初回測位で地図を寄せ、拒否されたら設定アプリへの導線を出す必要があるため。
///
/// `CLLocationManager` ではなく iOS 17以降の `CLLocationUpdate.liveUpdates()` を使う。
/// `CLLocationUpdate` / `CLLocationUpdate.Updates` が `Sendable` なので、
/// 非Sendableな `CLLocationManager` とデリゲートを `@MainActor` に橋渡しする必要がない。
///
/// 位置情報の許可ダイアログは `requestWhenInUseAuthorization()` では出さない。
/// iOS 18以降は `liveUpdates()` の反復開始が when-in-use 目的の `CLServiceSession` を
/// 暗黙に保持し、それ自体がダイアログを表示する。明示的な `CLServiceSession` が必要なのは
/// `.always` 相当の常時許可を取る場合だけで、前景のみの本アプリでは不要。
///
/// 停止APIは存在しない。ループを抜けるかTaskのキャンセルが停止であり、
/// SwiftUIの `.task {}` から駆動して画面離脱で自動的に止まることを前提にしている。
@MainActor
@Observable
final class CurrentLocationService {
    /// 画面側が「待機中・取得中・エラー」を描き分けるための状態。
    nonisolated enum Status: Equatable, Sendable {
        /// 未開始、またはキャンセルされて停止した。
        case idle
        /// 許可ダイアログの表示中、もしくは初回の測位待ち。
        case permissionPending
        /// 位置が更新され続けている。
        case streaming
        /// 拒否・制限。ユーザーが設定を変えるまで回復しないため終端状態。
        case denied
        /// 一時的に測位できない。直近の座標は保持したまま回復を待つ。
        case unavailable
        /// 想定外のエラーでストリームが終了した。
        case failed(message: String)
    }

    /// 直近に取得できた現在地。測位前と拒否時はnil。
    private(set) var coordinate: CLLocationCoordinate2D?

    /// 画面側が描画を切り替えるための現在状態。
    private(set) var status: Status = .idle

    /// 「おおよその位置情報」だけを許可された状態かどうか。
    /// エラーではないので測位は続けるが、地図のズームや近傍検索の精度期待を下げる判断に使う。
    private(set) var isApproximateAccuracy: Bool = false

    init() {}

    /// 位置更新のストリームを反復し、1件ずつ状態へ反映する。
    /// 呼び出し側のTaskがキャンセルされるまで戻らない。
    func startUpdates() async {
        // 反復開始がダイアログ表示の契機になるため、先に「許可待ち」を見せておく。
        if status != .streaming { status = .permissionPending }
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                apply(update)
                // 拒否は終端。ストリームを掴み続けても回復しないので抜ける。
                if status == .denied { return }
            }
            // ストリームが自然終了した場合は再開できる状態へ戻す。
            finishIfRunning()
        } catch is CancellationError {
            // 画面離脱による停止は正常系。エラー表示にはしない。
            finishIfRunning()
        } catch {
            status = .failed(message: error.localizedDescription)
        }
    }

    /// 診断プロパティは複数同時に立つため、評価順序そのものがUIの見え方を決める。
    private func apply(_ update: CLLocationUpdate) {
        // 1. ダイアログ表示中は他の診断（insufficientlyInUse等）も同時に立つ。
        //    ここで打ち切らないと、ユーザーがまだ応答していない瞬間にエラーを描いてしまう。
        if update.authorizationRequestInProgress {
            status = .permissionPending
            return
        }

        // 2. 端末全体の位置情報サービスOFF → アプリ側では回復不能。
        // 3. このアプリに対する拒否。
        // 4. ペアレンタルコントロール等による制限。いずれもユーザー操作待ちの終端状態。
        if update.authorizationDeniedGlobally
            || update.authorizationDenied
            || update.authorizationRestricted {
            coordinate = nil
            isApproximateAccuracy = false
            status = .denied
            return
        }

        // 5. 本来は反復が暗黙のセッションを保持するので立たないが、
        //    競合時に立ちうる。終端ではないので回復待ちに留める。
        // 6. 前景条件を満たしていない / 7. 測位そのものが不可。
        //    どちらも一時的なので直近の座標は捨てない。
        if update.serviceSessionRequired
            || update.insufficientlyInUse
            || update.locationUnavailable {
            status = .unavailable
            return
        }

        // 8. 精度低下は失敗ではないので、フラグだけ更新して測位は続ける。
        isApproximateAccuracy = update.accuracyLimited

        // 9. 座標が来たときだけ更新する。
        //    locationがnilなのは停止（stationary）等で更新が意図的に止まっている場合で、
        //    エラーではないため直近の座標を維持する。
        if let location = update.location {
            coordinate = location.coordinate
            status = .streaming
        } else if coordinate != nil {
            status = .streaming
        } else {
            status = .permissionPending
        }
    }

    /// 終端状態（denied / failed）は上書きせず、稼働中だった場合だけ待機に戻す。
    private func finishIfRunning() {
        if status == .streaming || status == .permissionPending {
            status = .idle
        }
    }
}
