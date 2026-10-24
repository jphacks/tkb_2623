#!/usr/bin/env bash
# Swift 6.2+。iOS UI・秘密情報を使わず、現行Repository/Modelを通信モックで検証。
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/gourmet-repositories.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
mkdir -p "$build_dir/Sources/GourmetShareMap" "$build_dir/Tests/GourmetShareMapTests"
cp "$repo_dir"/GourmetShareMap/Repositories/*.swift "$build_dir/Sources/GourmetShareMap/"
cp "$repo_dir"/GourmetShareMap/Models/*.swift "$build_dir/Sources/GourmetShareMap/"
cp "$repo_dir"/GourmetShareMapTests/*RepositoryTests.swift "$build_dir/Tests/GourmetShareMapTests/"
cat > "$build_dir/Sources/GourmetShareMap/SupabaseManager.swift" <<'SWIFT'
import Supabase
nonisolated final class SupabaseManager: Sendable {
    static let shared = SupabaseManager()
    var client: SupabaseClient { fatalError("Tests must inject their client") }
}
SWIFT
python3 - "$build_dir/Package.swift" <<'PY'
import json, os, pathlib, sys
sdk = os.environ.get('REPOSITORY_TEST_SDK_PATH')
dependency = '.package(path: ' + json.dumps(sdk) + ')' if sdk else '.package(url: "https://github.com/supabase/supabase-swift", exact: "2.55.4")'
identity = pathlib.Path(sdk).name.lower() if sdk else 'supabase-swift'
pathlib.Path(sys.argv[1]).write_text('''// swift-tools-version:6.2
import PackageDescription
let package = Package(name: "RepositoryChecks", platforms: [.macOS(.v13)],
    dependencies: [DEPENDENCY], targets: [
        .target(name: "GourmetShareMap", dependencies: [.product(name: "Supabase", package: "IDENTITY")],
            swiftSettings: [.defaultIsolation(MainActor.self), .swiftLanguageMode(.v5)]),
        .testTarget(name: "GourmetShareMapTests", dependencies: ["GourmetShareMap", .product(name: "Supabase", package: "IDENTITY")],
            swiftSettings: [.swiftLanguageMode(.v5)])])
'''.replace('DEPENDENCY', dependency).replace('IDENTITY', identity))
PY
# 同じscratchディレクトリを使うと依存SDKのビルドを再利用できる。
swift test --package-path "$build_dir" \
    --scratch-path "${REPOSITORY_TEST_BUILD_DIR:-${TMPDIR:-/tmp}/gourmet-repository-build}" --jobs 4
