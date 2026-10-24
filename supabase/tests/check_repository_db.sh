#!/usr/bin/env bash
# 一時DBだけに既存schemaを適用。Supabase Storageサービス自体は起動しない。
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
container_name="gourmet-repository-db-$$"
docker info >/dev/null 2>&1 || { echo 'Dockerを起動し、実行権限を確認してください。' >&2; exit 1; }
cleanup() { docker rm -f "$container_name" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker run --detach --rm --name "$container_name" --network none \
    --env POSTGRES_PASSWORD=local-repository-test-only postgres:17-alpine >/dev/null
ready=false
for attempt in {1..30}; do
    if docker exec "$container_name" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1; then ready=true; break; fi
    sleep 1
done
[[ "$ready" == true ]] || { echo 'PostgreSQLの起動に失敗しました。' >&2; exit 1; }
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
create role authenticated nologin;
create role anon nologin;
create schema auth;
create table auth.users (id uuid primary key, email text);
create function auth.uid() returns uuid language sql stable as $$
    select (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')::uuid
$$;
grant usage on schema auth to authenticated, anon;
grant execute on function auth.uid() to authenticated, anon;
alter default privileges in schema public grant all on tables to authenticated, anon;
SQL
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$script_dir/../schema.sql"
shopt -s nullglob
for sql in "$script_dir/store.sql" "$script_dir"/repository_*.sql; do
    [[ -f "$sql" ]] || continue
    echo "検証: $(basename "$sql")"
    docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$sql"
done
echo '成功: Repository用SQL・RLSテスト（終了時に一時DBを削除）'
