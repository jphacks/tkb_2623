#!/usr/bin/env bash
# Disposable PostgreSQL only. Never connects to a linked Supabase project.
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
container_name="mogumap-ai-db-$$"
cleanup() { docker rm -f "$container_name" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker run --detach --rm --name "$container_name" --network none \
  --env POSTGRES_PASSWORD=local-ai-test-only postgres:17-alpine >/dev/null
ready=false
for attempt in {1..30}; do
  if docker exec "$container_name" pg_isready -U postgres >/dev/null 2>&1; then ready=true; break; fi
  sleep 1
done
[[ "$ready" == true ]] || { echo 'PostgreSQL did not start' >&2; exit 1; }
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
create role authenticated nologin;
create role anon nologin;
create role service_role nologin bypassrls;
create schema auth;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
grant usage on schema auth to authenticated, anon, service_role;
alter default privileges in schema public grant all on tables to authenticated, anon, service_role;
SQL
for file in 20261024025750_initial_schema.sql 20261024100000_ai_backend_schema.sql 20261025120000_ai_background_training.sql; do
  docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$script_dir/../migrations/$file"
done
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 < "$script_dir/ai_training.sql"
echo 'Success: AI training triggers, leases, publication, retries, and client permissions'
