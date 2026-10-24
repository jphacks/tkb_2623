#!/usr/bin/env bash
# Nearby Search → 最寄り店舗 → 実RecordRepository → ローカルPostgREST/PostgreSQL。
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/../.." && pwd)"
mode="${1:---live}"
if [[ "$mode" != --live && "$mode" != --mock ]]; then
    echo '使い方: bash supabase/tests/check_nearby_store_local.sh [--live|--mock] [緯度 経度]' >&2
    exit 1
fi
if [[ $# != 0 && $# != 1 && $# != 3 ]]; then
    echo '緯度・経度は両方指定してください。' >&2
    exit 1
fi
export NEARBY_CHECK_MODE="${mode#--}"
export NEARBY_CHECK_LATITUDE="${2:-35.713329}"
export NEARBY_CHECK_LONGITUDE="${3:-139.7617112}"
for tool in docker swift python3 curl; do
    command -v "$tool" >/dev/null || { echo "$tool が必要です。" >&2; exit 1; }
done
docker info >/dev/null 2>&1 || { echo 'Dockerを起動し、実行権限を確認してください。' >&2; exit 1; }

if [[ "$mode" == --live && -z "${GOOGLE_MAPS_API_KEY:-}" ]]; then
    # キーを引数・ログ・一時Swiftソースへ書き出さない。
    GOOGLE_MAPS_API_KEY="$(python3 - "$repo_dir/GourmetShareMap/Services/Places/GoogleMapsConfig.swift" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
match = re.search(r'\bstatic\s+let\s+apiKey\s*=\s*"([^"\n]+)"', path.read_text()) if path.exists() else None
if not match or match[1] == 'YOUR_GOOGLE_MAPS_API_KEY':
    sys.exit('GOOGLE_MAPS_API_KEY環境変数、またはGoogleMapsConfig.swiftのapiKeyを設定してください。')
print(match[1])
PY
)"
    export GOOGLE_MAPS_API_KEY
fi

build_dir="${NEARBY_CHECK_BUILD_DIR:-${TMPDIR:-/tmp}/gourmet-nearby-store-check}"
mkdir -p "$build_dir/Sources/Check"
cp "$repo_dir/GourmetShareMap/Models/StoreRecord.swift" \
   "$repo_dir/GourmetShareMap/Repositories/RecordRepository.swift" \
   "$repo_dir/GourmetShareMap/Services/Places/FindNearestShop.swift" \
   "$repo_dir/GourmetShareMap/Services/Places/PlaceCategoryClassifier.swift" \
   "$script_dir/nearby-store/IntegrationCheck.swift" "$build_dir/Sources/Check/"
cat > "$build_dir/Sources/Check/LocalConfig.swift" <<'SWIFT'
import Foundation
import Supabase
enum GoogleMapsConfig {
    static var apiKey: String { ProcessInfo.processInfo.environment["GOOGLE_MAPS_API_KEY"] ?? "" }
}
@MainActor
final class SupabaseManager {
    static let shared = SupabaseManager()
    var client: SupabaseClient { fatalError("結合テストはローカル用clientを注入します") }
}
SWIFT
python3 - "$build_dir/Package.swift" <<'PY'
import json, os, pathlib, sys
sdk = os.environ.get('NEARBY_CHECK_SDK_PATH')
dependency = f'.package(path: {json.dumps(sdk)})' if sdk else '.package(url: "https://github.com/supabase/supabase-swift", exact: "2.55.4")'
identity = pathlib.Path(sdk).name.lower() if sdk else 'supabase-swift'
pathlib.Path(sys.argv[1]).write_text('''// swift-tools-version:6.2
import PackageDescription
let package = Package(name: "NearbyStoreCheck", platforms: [.macOS(.v13)],
    dependencies: [DEPENDENCY],
    targets: [.executableTarget(name: "Check", dependencies: [.product(name: "Supabase", package: "IDENTITY")],
                               swiftSettings: [.swiftLanguageMode(.v5)])])
'''.replace('DEPENDENCY', dependency).replace('IDENTITY', identity))
PY
echo '実アプリの検索・保存ソースを使って結合テストをビルドします。'
swift build --package-path "$build_dir" --jobs 4
binary_dir="$(swift build --package-path "$build_dir" --show-bin-path)"

suffix="$$"
db_container="gourmet-nearby-db-$suffix"
rest_container="gourmet-nearby-rest-$suffix"
network="gourmet-nearby-net-$suffix"
cleanup() {
    docker rm -f "$rest_container" "$db_container" >/dev/null 2>&1 || true
    docker network rm "$network" >/dev/null 2>&1 || true
}
trap cleanup EXIT
docker network create "$network" >/dev/null
docker run --detach --rm --name "$db_container" --network "$network" --network-alias db \
    --env POSTGRES_PASSWORD=local-nearby-test-only postgres:17-alpine >/dev/null
db_ready=false
for attempt in {1..30}; do
    if docker exec "$db_container" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1; then
        db_ready=true; break
    fi
    sleep 1
done
[[ "$db_ready" == true ]] || { docker logs "$db_container" >&2; exit 1; }
docker exec -i "$db_container" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
create role authenticated nologin;
create role anon nologin;
create role authenticator login noinherit password 'local-rest-only';
grant authenticated, anon to authenticator;
create schema auth;
create table auth.users (id uuid primary key, email text);
create function auth.uid() returns uuid language sql stable as $$
    select (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')::uuid
$$;
grant usage on schema auth to authenticated, anon;
grant execute on function auth.uid() to authenticated, anon;
alter default privileges in schema public grant all on tables to authenticated, anon;
SQL
docker exec -i "$db_container" psql -U postgres -v ON_ERROR_STOP=1 < "$repo_dir/supabase/migrations/20261024025750_initial_schema.sql"
docker exec -i "$db_container" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
insert into auth.users (id, email) values ('c0240000-0000-4000-8000-000000000001', 'nearby-check@example.invalid');
insert into public."user" (id, user_name, name) values ('c0240000-0000-4000-8000-000000000001', 'nearby_check', '結合テストユーザー');
SQL
docker run --detach --rm --name "$rest_container" --network "$network" \
    --publish 127.0.0.1::3000 \
    --env PGRST_DB_URI=postgres://authenticator:local-rest-only@db:5432/postgres \
    --env PGRST_DB_ANON_ROLE=anon --env PGRST_DB_SCHEMAS=public \
    --env PGRST_JWT_SECRET=local-nearby-integration-secret-32-characters \
    postgrest/postgrest:v12.2.3 >/dev/null
rest_port="$(docker port "$rest_container" 3000/tcp)"
export NEARBY_CHECK_REST_URL="http://127.0.0.1:${rest_port##*:}"
rest_ready=false
for attempt in {1..30}; do
    if curl --silent --fail --max-time 1 "$NEARBY_CHECK_REST_URL/" >/dev/null; then
        rest_ready=true; break
    fi
    sleep 1
done
[[ "$rest_ready" == true ]] || { docker logs "$rest_container" >&2; exit 1; }
NEARBY_CHECK_JWT="$(python3 - <<'PY'
import base64, hashlib, hmac, json, time
def encode(value):
    return base64.urlsafe_b64encode(json.dumps(value).encode()).rstrip(b'=')
body = encode({'alg':'HS256','typ':'JWT'}) + b'.' + encode({
    'sub':'c0240000-0000-4000-8000-000000000001','role':'authenticated','exp':int(time.time())+3600})
signature = base64.urlsafe_b64encode(hmac.new(b'local-nearby-integration-secret-32-characters', body, hashlib.sha256).digest()).rstrip(b'=')
print((body+b'.'+signature).decode())
PY
)"
export NEARBY_CHECK_JWT
echo "結合テストを実行します（Google: $NEARBY_CHECK_MODE / DB: ローカル実DB）。"
"$binary_dir/Check"
docker exec "$db_container" psql -U postgres -c \
    'select name, category, google_place_id, repeat_num, latitude, longitude from public.store;'
echo '終了時に一時DB・PostgREST・Dockerネットワークを削除します。'
