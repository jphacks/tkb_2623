// CLIテストとしてコンパイルするときだけ有効。
#if PLACES_API_CLI
import Foundation
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
        let args = CommandLine.arguments
        guard args.count == 3,
              let latitude = Double(args[1]),
              let longitude = Double(args[2]) else {
            FileHandle.standardError.write(Data("使い方: PlacesAPITest 緯度 経度\n".utf8))
            exit(1)
        }

        do {
            let shops = try await findNearestShop(latitude: latitude, longitude: longitude)
            print(shops)
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
}
#endif
