-- Supabaseダッシュボード > SQL Editor に貼り付けて実行してください。
-- Sign in with Apple初回ログイン時に、クライアント側から upsert されるプロフィールテーブル。

create table if not exists public.profiles (
    id uuid primary key references auth.users (id) on delete cascade,
    email text,
    full_name text,
    created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "Users can view own profile"
    on public.profiles for select
    using (auth.uid() = id);

create policy "Users can insert own profile"
    on public.profiles for insert
    with check (auth.uid() = id);

create policy "Users can update own profile"
    on public.profiles for update
    using (auth.uid() = id)
    with check (auth.uid() = id);
