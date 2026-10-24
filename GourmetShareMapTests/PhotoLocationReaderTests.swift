//
//  PhotoLocationReaderTests.swift
//  GourmetShareMapTests
//

import CoreGraphics
import CoreLocation
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import GourmetShareMap

struct PhotoLocationReaderTests {

    /// 指定したメタデータを持つ 1x1 の JPEG を作る。
    private func makeJPEG(properties: [String: Any]) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test func readsLocationWithHemisphereRefs() throws {
        let data = try makeJPEG(properties: [
            kCGImagePropertyGPSDictionary as String: [
                kCGImagePropertyGPSLatitude as String: 33.8688,
                kCGImagePropertyGPSLatitudeRef as String: "S",
                kCGImagePropertyGPSLongitude as String: 151.2093,
                kCGImagePropertyGPSLongitudeRef as String: "E",
            ],
        ])
        let location = try #require(PhotoLocationReader.location(from: data))
        #expect(abs(location.latitude - -33.8688) < 0.0001)
        #expect(abs(location.longitude - 151.2093) < 0.0001)
    }

    @Test func returnsNilWithoutGPS() throws {
        let data = try makeJPEG(properties: [:])
        #expect(PhotoLocationReader.location(from: data) == nil)
        #expect(PhotoLocationReader.takenAt(from: data) == nil)
    }

    @Test func readsTakenAtWithOffset() throws {
        let data = try makeJPEG(properties: [
            kCGImagePropertyExifDictionary as String: [
                kCGImagePropertyExifDateTimeOriginal as String: "2026:10:24 12:30:00",
                kCGImagePropertyExifOffsetTimeOriginal as String: "+09:00",
            ],
        ])
        let date = try #require(PhotoLocationReader.takenAt(from: data))
        #expect(date == ISO8601DateFormatter().date(from: "2026-10-24T03:30:00Z"))
    }

    @Test func returnsNilForNonImageData() {
        #expect(PhotoLocationReader.location(from: Data("not an image".utf8)) == nil)
    }
}
