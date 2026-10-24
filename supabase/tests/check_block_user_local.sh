#!/usr/bin/env bash
# Docker内の使い捨てDBに全マイグレーションを適用し、ブロック機能のRLS・RPCを確認する。
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
supabase_dir="$(cd -- "$script_dir/.." && pwd)"
container_name="gourmet-block-check-$$"

command -v docker >/dev/null || { echo 'Dockerをインストールして起動してください。' >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo 'Dockerに接続できません。Dockerを起動し、実行権限を確認してください。' >&2; exit 1; }

cleanup() { docker rm -f "$container_name" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo '一時PostgreSQLを起動します（ホストへのポート公開なし）。'
docker run --detach --rm --name "$container_name" --network none \
    --env POSTGRES_PASSWORD=local-block-check-only postgres:17-alpine >/dev/null

db_ready=false
for attempt in {1..30}; do
    if docker exec "$container_name" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1; then
        db_ready=true
        break
    fi
    sleep 1
done
if [[ "$db_ready" != true ]]; then
    docker logs "$container_name" >&2
    echo 'PostgreSQLの起動を確認できませんでした。' >&2
    exit 1
fi

# Supabase本体を起動せず、スキーマが参照するAuth要素のみ用意する。
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

echo '既存の全マイグレーションを適用します。'
for migration in "$supabase_dir"/migrations/*.sql; do
    echo "  適用: $(basename "$migration")"
    docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$migration"
done

echo 'ブロック機能のRLS・RPCをテストします（テストデータはROLLBACK）。'
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$script_dir/block_user.sql"

echo '成功: ブロック機能のSQL・RLSテスト（終了時に一時DBを削除）'
