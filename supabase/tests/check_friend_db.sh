#!/usr/bin/env bash
# Docker内の使い捨てDBに supabase/migrations を順に適用し、
# user_name の自動採番・フレンド申請/承認・ユーザー検索のSQL・RLSを確認する。
# Supabase本体（Auth・Storageサービス）は起動せず、スキーマが参照する最小構成だけを用意する。
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
migrations_dir="$(cd -- "$script_dir/../migrations" && pwd)"
container_name="gourmet-friend-check-$$"

command -v docker >/dev/null || { echo 'Dockerをインストールして起動してください。' >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo 'Dockerに接続できません。Dockerを起動し、実行権限を確認してください。' >&2; exit 1; }

cleanup() { docker rm -f "$container_name" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo '一時PostgreSQLを起動します（ホストへのポート公開なし）。'
docker run --detach --rm --name "$container_name" --network none \
    --env POSTGRES_PASSWORD=local-friend-check-only postgres:17-alpine >/dev/null

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

run_sql() { docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 --quiet --output=/dev/null "$@"; }

# Auth・Storage のうち、migration とテストが参照する要素だけを用意する。
run_sql <<'SQL'
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

create schema storage;
create table storage.buckets (id text primary key, name text not null, public boolean not null default false);
create table storage.objects (
    id uuid primary key default gen_random_uuid(),
    bucket_id text not null references storage.buckets (id),
    name text not null
);
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as $$
    select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1]
$$;
grant usage on schema storage to authenticated, anon;
grant select, insert, update, delete on storage.objects to authenticated;
SQL

# user_name を必須にする migration より前の状態で、既存データの補完を確認するための行を入れる。
apply_migration() {
    echo "適用: $(basename "$1")"
    run_sql < "$1"
}
legacy_seeded=false
for migration in "$migrations_dir"/*.sql; do
    if [[ "$legacy_seeded" == false && "$(basename "$migration")" > "20261024150000" ]]; then
        echo '投入: user_name 補完前の既存データ'
        run_sql < "$script_dir/friend_legacy_seed.sql"
        legacy_seeded=true
    fi
    apply_migration "$migration"
done

for sql in "$script_dir"/friend_user_name.sql "$script_dir"/friend_request.sql "$script_dir"/friend_search.sql; do
    echo "検証: $(basename "$sql")"
    run_sql < "$sql"
done

echo '成功: user_name の自動採番・フレンド申請/承認・ユーザー検索のSQL・RLSを確認しました（終了時に一時DBを削除）。'
