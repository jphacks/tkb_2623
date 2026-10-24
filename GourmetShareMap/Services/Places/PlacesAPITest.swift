// CLI用のフラグを指定した場合だけ有効。通常のiOSアプリには影響しません。
#if PLACES_API_CLI
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if os(Windows)
import WinSDK
import ucrt
#elseif canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@main
struct PlacesAPITest {
    static func main() async {
        #if os(Windows)
        _ = SetConsoleOutputCP(65001)
        #endif
        let args = Array(CommandLine.arguments.dropFirst())
        if args == ["--help"] || args == ["-h"] {
            print("使い方: PlacesAPITest [緯度 経度]（省略時: LinuxのGeoClueから現在地を取得）")
            return
        }
        let key = GoogleMapConfig.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard args.isEmpty || args.count == 2 else { fail("引数は省略するか、緯度 経度を指定してください。") }
        guard !key.isEmpty, key != "YOUR_GOOGLE_MAPS_API_KEY" else {
            fail("GoogleMapConfig.swift の apiKey に実際のAPIキーを設定してください。")
        }
        do {
            let coordinate: Coordinate
            if args.isEmpty {
                print("現在地を取得しています（最大30秒）...")
                coordinate = try await currentLocation()
            } else {
                coordinate = try Coordinate(latitude: args[0], longitude: args[1])
            }
            print("検索位置: 緯度 \(coordinate.latitude), 経度 \(coordinate.longitude) / 半径1km")
            var request = URLRequest(url: URL(string: "https://places.googleapis.com/v1/places:searchNearby")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
            request.setValue("places.id,places.displayName,places.location,places.primaryType,places.types",
                             forHTTPHeaderField: "X-Goog-FieldMask")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "languageCode": "ja",
                "includedTypes": ["restaurant", "cafe"],
                "maxResultCount": 5,
                "rankPreference": "DISTANCE",
                "locationRestriction": ["circle": [
                    "center": ["latitude": coordinate.latitude, "longitude": coordinate.longitude],
                    "radius": 1000.0,
                ]],
            ])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                fail("HTTPレスポンスを取得できませんでした。")
            }
            guard (200..<300).contains(http.statusCode) else {
                let detail = String(decoding: data, as: UTF8.self)
                    .replacingOccurrences(of: key, with: "[REDACTED]")
                fail("APIエラー (HTTP \(http.statusCode)):\n\(detail)")
            }
            let result = try JSONSerialization.jsonObject(with: data)
            let places = (result as? [String: Any])?["places"] as? [[String: Any]] ?? []
            for (index, place) in places.enumerated() {
                print("\n[\(index + 1)]")
                print(formatPlace(place).replacingOccurrences(of: key, with: "[REDACTED]"))
            }
            print("\n取得件数: \(places.count)")
        } catch {
            fail("実行エラー: \(error.localizedDescription.replacingOccurrences(of: key, with: "[REDACTED]"))")
        }
    }

    // 順序はtypesが複数カテゴリに一致した場合の優先順位。「その他」は最後。
    static let categoryRules: [(name: String, types: Set<String>)] = [
        ("和食", "japanese_restaurant sushi_restaurant tonkatsu_restaurant yakitori_restaurant seafood_restaurant hot_pot_restaurant"),
        ("ラーメン・麺類", "ramen_restaurant noodle_shop chinese_noodle_restaurant"),
        ("焼肉・肉料理", "yakiniku_restaurant korean_barbecue_restaurant mongolian_barbecue_restaurant steak_house barbecue_restaurant chicken_restaurant chicken_wings_restaurant"),
        ("中華", "chinese_restaurant cantonese_restaurant dim_sum_restaurant dumpling_restaurant taiwanese_restaurant"),
        ("カレー", "japanese_curry_restaurant indian_restaurant north_indian_restaurant south_indian_restaurant pakistani_restaurant bangladeshi_restaurant sri_lankan_restaurant"),
        ("アジア・エスニック", "korean_restaurant thai_restaurant vietnamese_restaurant indonesian_restaurant malaysian_restaurant filipino_restaurant burmese_restaurant cambodian_restaurant tibetan_restaurant asian_restaurant asian_fusion_restaurant middle_eastern_restaurant turkish_restaurant lebanese_restaurant israeli_restaurant persian_restaurant afghani_restaurant moroccan_restaurant african_restaurant ethiopian_restaurant kebab_shop shawarma_restaurant falafel_restaurant gyro_restaurant"),
        ("洋食・西洋料理", "western_restaurant italian_restaurant pizza_restaurant french_restaurant bistro spanish_restaurant tapas_restaurant basque_restaurant portuguese_restaurant greek_restaurant mediterranean_restaurant german_restaurant bavarian_restaurant austrian_restaurant swiss_restaurant fondue_restaurant belgian_restaurant dutch_restaurant danish_restaurant scandinavian_restaurant british_restaurant irish_restaurant fish_and_chips_restaurant european_restaurant eastern_european_restaurant polish_restaurant czech_restaurant hungarian_restaurant croatian_restaurant romanian_restaurant russian_restaurant ukrainian_restaurant oyster_bar_restaurant american_restaurant californian_restaurant cajun_restaurant soul_food_restaurant southwestern_us_restaurant hawaiian_restaurant australian_restaurant mexican_restaurant tex_mex_restaurant taco_restaurant burrito_restaurant latin_american_restaurant south_american_restaurant brazilian_restaurant argentinian_restaurant peruvian_restaurant chilean_restaurant colombian_restaurant cuban_restaurant caribbean_restaurant"),
        ("ファストフード・食堂", "fast_food_restaurant hamburger_restaurant hot_dog_restaurant hot_dog_stand sandwich_shop deli salad_shop soup_restaurant snack_bar pizza_delivery meal_takeaway meal_delivery food_court cafeteria diner family_restaurant buffet_restaurant breakfast_restaurant brunch_restaurant"),
        ("カフェ・喫茶", "cafe coffee_shop coffee_stand coffee_roastery tea_house cat_cafe dog_cafe juice_shop acai_shop"),
        ("パン", "bakery bagel_shop"),
        ("スイーツ", "cake_shop pastry_shop donut_shop dessert_restaurant dessert_shop ice_cream_shop confectionery candy_store chocolate_shop chocolate_factory"),
        ("居酒屋・バー", "japanese_izakaya_restaurant bar bar_and_grill pub irish_pub gastropub brewpub brewery beer_garden wine_bar winery cocktail_bar lounge_bar sports_bar hookah_bar"),
        ("その他", "restaurant fusion_restaurant fine_dining_restaurant vegan_restaurant vegetarian_restaurant halal_restaurant"),
    ].map { (name: $0.0, types: Set($0.1.split(separator: " ").map(String.init))) }

    static func category(primaryType: String?, types: [String]) -> String {
        // 主カテゴリが具体的なら優先する。汎用のrestaurant等は詳細typesで補完する。
        let specificRules = categoryRules.dropLast()
        if let primaryType,
           let rule = specificRules.first(where: { $0.types.contains(primaryType) }) {
            return rule.name
        }
        let typeSet = Set(types)
        return specificRules.first(where: { !$0.types.isDisjoint(with: typeSet) })?.name ?? "その他"
    }

    static func formatPlace(_ place: [String: Any]) -> String {
        let id = place["id"] as? String ?? "不明"
        let name = (place["displayName"] as? [String: Any])?["text"] as? String ?? "不明"
        let location = place["location"] as? [String: Any]
        let latitude = (location?["latitude"] as? Double).map { String($0) } ?? "不明"
        let longitude = (location?["longitude"] as? Double).map { String($0) } ?? "不明"
        let label = category(primaryType: place["primaryType"] as? String,
                             types: place["types"] as? [String] ?? [])
        return """
        Place ID: \(id)
        店名: \(name)
        緯度・経度: \(latitude), \(longitude)
        算出したカテゴリ: \(label)
        """
    }

    struct Coordinate {
        let latitude: Double
        let longitude: Double

        init(latitude: String, longitude: String) throws {
            guard let lat = Double(latitude), lat.isFinite, (-90...90).contains(lat),
                  let lon = Double(longitude), lon.isFinite, (-180...180).contains(lon) else {
                throw LocationError(message: "緯度は-90〜90、経度は-180〜180の数値で指定してください。")
            }
            self.latitude = lat
            self.longitude = lon
        }
    }

    struct LocationError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func currentLocation() async throws -> Coordinate {
        #if os(Linux)
        let paths = [
            "/usr/libexec/geoclue-2.0/demos/where-am-i",
            "/usr/lib/geoclue-2.0/demos/where-am-i",
            "/usr/lib64/geoclue-2.0/demos/where-am-i",
        ]
        guard let executable = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }),
              FileManager.default.isExecutableFile(atPath: "/usr/bin/stdbuf") else {
            throw LocationError(message: "GeoClueのwhere-am-iとstdbufが必要です。README.mdを確認するか、緯度 経度を引数で指定してください。")
        }
        // 子プロセスの出力をファイル経由で読み、位置取得後に終了する。
        // stdbufでバッファリングを解除し、更新待ちで読み取りが止まるのを防ぐ。
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: outputURL, options: .withoutOverwriting)
        let output = try FileHandle(forWritingTo: outputURL)
        defer {
            try? output.close()
            try? FileManager.default.removeItem(at: outputURL)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/stdbuf")
        process.arguments = ["-oL", executable]
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        process.environment = environment
        process.standardOutput = output
        process.standardError = output
        try process.run()
        defer {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 30
        repeat {
            let text = String(decoding: try Data(contentsOf: outputURL), as: UTF8.self)
            if let coordinate = try parseGeoClue(text) { return coordinate }
            if !process.isRunning {
                throw LocationError(message: "GeoClueで現在地を取得できませんでした。位置情報の許可とサービス設定を確認してください。\n\(text)")
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        } while ProcessInfo.processInfo.systemUptime < deadline
        throw LocationError(message: "現在地の取得が30秒でタイムアウトしました。位置情報の許可・GeoClueを確認するか、緯度 経度を指定してください。")
        #else
        throw LocationError(message: "現在地の自動取得はLinuxのGeoClueに対応しています。このOSでは緯度 経度を引数で指定してください。")
        #endif
    }

    static func parseGeoClue(_ text: String) throws -> Coordinate? {
        func value(_ name: String) -> String? {
            let pattern = "(?m)^\\s*" + name + ":\\s*([-+]?[0-9]+(?:\\.[0-9]+)?)"
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
        guard let latitude = value("Latitude"), let longitude = value("Longitude") else { return nil }
        return try Coordinate(latitude: latitude, longitude: longitude)
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
#endif
