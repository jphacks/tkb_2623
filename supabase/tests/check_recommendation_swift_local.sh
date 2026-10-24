#!/usr/bin/env bash
# Run the actual Swift repository and URLProtocol tests without an iOS UI or API keys.
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/../.." && pwd)"
build_dir="${RECOMMENDATION_CHECK_BUILD_DIR:-${TMPDIR:-/tmp}/mogumap-recommendation-check}"
mkdir -p "$build_dir/Sources/GourmetShareMap" "$build_dir/Tests/GourmetShareMapTests"
cp "$repo_dir/GourmetShareMap/Models/Recommendation.swift" \
   "$repo_dir/GourmetShareMap/Repositories/RecommendationRepository.swift" \
   "$build_dir/Sources/GourmetShareMap/"
cp "$repo_dir/GourmetShareMapTests/RecommendationRepositoryTests.swift" \
   "$build_dir/Tests/GourmetShareMapTests/"
cat > "$build_dir/Sources/GourmetShareMap/SupabaseManager.swift" <<'SWIFT'
import Supabase
@MainActor
final class SupabaseManager {
    static let shared = SupabaseManager()
    var client: SupabaseClient { fatalError("Tests must inject their client") }
}
SWIFT
python3 - "$build_dir/Package.swift" <<'PY'
import json, os, pathlib, sys
sdk = os.environ.get('RECOMMENDATION_CHECK_SDK_PATH')
dependency = f'.package(path: {json.dumps(sdk)})' if sdk else '.package(url: "https://github.com/supabase/supabase-swift", exact: "2.55.4")'
identity = pathlib.Path(sdk).name.lower() if sdk else 'supabase-swift'
pathlib.Path(sys.argv[1]).write_text('''// swift-tools-version:6.2
import PackageDescription
let package = Package(name: "RecommendationChecks", platforms: [.macOS(.v13)],
    dependencies: [DEPENDENCY],
    targets: [
        .target(name: "GourmetShareMap", dependencies: [.product(name: "Supabase", package: "IDENTITY")],
                swiftSettings: [.defaultIsolation(MainActor.self), .swiftLanguageMode(.v5)]),
        .testTarget(name: "GourmetShareMapTests", dependencies: ["GourmetShareMap", .product(name: "Supabase", package: "IDENTITY")],
                    swiftSettings: [.swiftLanguageMode(.v5)])
    ])
'''.replace('DEPENDENCY', dependency).replace('IDENTITY', identity))
PY
swift test --package-path "$build_dir" --jobs 4 --filter RecommendationRepositoryTests
