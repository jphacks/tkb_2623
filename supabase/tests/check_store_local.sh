#!/usr/bin/env bash
# Docker内の使い捨てDBで、既存schema.sqlの生成・RLS・疑似データ保存を確認する。
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
supabase_dir="$(cd -- "$script_dir/.." && pwd)"
container_name="gourmet-store-check-$$"

command -v docker >/dev/null || { echo 'Dockerをインストールして起動してください。' >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo 'Dockerに接続できません。Dockerを起動し、実行権限を確認してください。' >&2; exit 1; }

cleanup() { docker rm -f "$container_name" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo '一時PostgreSQLを起動します（ホストへのポート公開なし）。'
docker run --detach --rm --name "$container_name" --network none \
    --env POSTGRES_PASSWORD=local-store-check-only postgres:17-alpine >/dev/null

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

echo '既存schema.sqlを適用します。'
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$supabase_dir/migrations/20261024025750_initial_schema.sql"

echo '保存・フレンド共有・RLSをテストします（テストデータはROLLBACK）。'
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$script_dir/store.sql"

echo '生成したテーブル・storeの定義と、疑似データ2件を表示します。'
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
\dt public.*
\d public.store
insert into auth.users (id, email)
values ('b0240000-0000-4000-8000-000000000001', 'local-demo@example.invalid');
insert into public."user" (id, user_name, name)
values ('b0240000-0000-4000-8000-000000000001', 'local_demo', '確認用ユーザー');
insert into public.store (user_id, name, category, reputation, google_place_id, memo, repeat_num, latitude, longitude)
values
    ('b0240000-0000-4000-8000-000000000001', 'サンプル喫茶', 'カフェ・喫茶', 4, 'local-demo-cafe', '保存確認', 1, 35.6812, 139.7671),
    ('b0240000-0000-4000-8000-000000000001', 'サンプル食堂', '和食', 5, null, '手入力の店舗', 2, 35.6895, 139.6917);
select name, category, reputation, repeat_num, memo, latitude, longitude from public.store order by name;
do $$
begin
    assert to_regclass('public.store') is not null, 'storeテーブルがありません';
    assert (select count(*) = 2 from public.store), '疑似データが保存されていません';
end $$;
SQL

echo '成功: storeテーブルの生成・疑似データ2件の保存・RLSを確認しました。'
echo '終了時に一時DBとコンテナを削除します。'
