//
//  PhotoLocationReader.swift
//  GourmetShareMap
//

import CoreLocation
import ImageIO

/// 写真データの EXIF / GPS メタデータから撮影位置・撮影日時を読み取る。取れなければ nil。
nonisolated enum PhotoLocationReader {
    static func location(from data: Data) -> CLLocationCoordinate2D? {
        guard
            let gps = properties(of: data)?[kCGImagePropertyGPSDictionary as String] as? [String: Any],
            let latitude = gps[kCGImagePropertyGPSLatitude as String] as? Double,
            let longitude = gps[kCGImagePropertyGPSLongitude as String] as? Double
        else { return nil }

        let latitudeRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String
        let longitudeRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String
        let coordinate = CLLocationCoordinate2D(
            latitude: latitudeRef == "S" ? -latitude : latitude,
            longitude: longitudeRef == "W" ? -longitude : longitude
        )
        // 0,0 は位置が書き込まれていない写真で入っていることがあるため無効扱いにする。
        guard CLLocationCoordinate2DIsValid(coordinate), !(latitude == 0 && longitude == 0) else { return nil }
        return coordinate
    }

    static func takenAt(from data: Data) -> Date? {
        guard
            let exif = properties(of: data)?[kCGImagePropertyExifDictionary as String] as? [String: Any],
            let dateTime = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String
        else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // OffsetTimeOriginal（例: "+09:00"）があればそのタイムゾーンで解釈し、なければ端末のタイムゾーンとみなす。
        if let offset = exif[kCGImagePropertyExifOffsetTimeOriginal as String] as? String {
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ssXXXXX"
            if let date = formatter.date(from: dateTime + offset) { return date }
        }
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = .current
        return formatter.date(from: dateTime)
    }

    private static func properties(of data: Data) -> [String: Any]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
    }
}
