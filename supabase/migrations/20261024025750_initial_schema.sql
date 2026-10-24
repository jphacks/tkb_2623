-- Supabaseダッシュボード > SQL Editor に貼り付けて実行してください。
-- PR-02: user / store / image / friend テーブルと RLS を定義する。
-- DB設計: https://app.notion.com/p/4009efa583a0806da4beee86faa9d15e
--
-- 方針:
--   - 自分の行: 全操作（select/insert/update/delete）可
--   - フレンド（自分がフォローしている相手）の store / image: 参照のみ
--   - friend は片方向フォロー方式（user_id が friend_id をフォローする）。
--     相互フォローではなく、フォローした相手の記録が見える一方通行の設計。
--     （2026-10-24 PR-02で決定。DB設計ページにも追記済み）
--
-- 既存の profiles テーブルは user に置き換える。
--
-- 実行順の注意: store / image の RLS ポリシーが friend テーブルを参照するため、
-- friend は store / image より前に作成すること。

drop table if exists public.profiles;

-- =========================================
-- user
-- =========================================
-- "user" はPostgreSQLの予約語のため、常に二重引用符で囲む。
create table if not exists public."user" (
    id uuid primary key references auth.users (id) on delete cascade,
    user_name text unique,
    name text,
    email text,
    bio text, -- 自己紹介。DB設計ページには未記載だったため追加（2026-10-24 PR-02）
    profile_image text, -- profile-images バケット内のオブジェクトパス
    created_at timestamptz not null default now()
);

alter table public."user" enable row level security;

create policy "user: select own row"
    on public."user" for select
    using (auth.uid() = id);

create policy "user: insert own row"
    on public."user" for insert
    with check (auth.uid() = id);

create policy "user: update own row"
    on public."user" for update
    using (auth.uid() = id)
    with check (auth.uid() = id);

create policy "user: delete own row"
    on public."user" for delete
    using (auth.uid() = id);

-- =========================================
-- friend（片方向フォロー: user_id が friend_id をフォローする）
-- store / image のRLSポリシーから参照されるため、先に作成する。
-- =========================================
create table if not exists public.friend (
    user_id uuid not null references public."user" (id) on delete cascade,
    friend_id uuid not null references public."user" (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (user_id, friend_id),
    check (user_id <> friend_id)
);

create index if not exists friend_friend_id_idx on public.friend (friend_id);

alter table public.friend enable row level security;

-- 自分がフォローしている/されている関係は参照可能（フォロー一覧・フォロワー一覧の両方で使うため）
create policy "friend: select own edges"
    on public.friend for select
    using (auth.uid() = user_id or auth.uid() = friend_id);

create policy "friend: insert own edges"
    on public.friend for insert
    with check (auth.uid() = user_id);

create policy "friend: delete own edges"
    on public.friend for delete
    using (auth.uid() = user_id);

-- =========================================
-- store
-- =========================================
create table if not exists public.store (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public."user" (id) on delete cascade,
    name text not null,
    category text,
    reputation numeric(2, 1) check (reputation >= 0 and reputation <= 5),
    google_place_id text,
    latitude double precision,
    longitude double precision,
    memo text,
    repeat_num integer not null default 0 check (repeat_num >= 0),
    created_at timestamptz not null default now()
);

create index if not exists store_user_id_idx on public.store (user_id);

alter table public.store enable row level security;

create policy "store: select own or friend's rows"
    on public.store for select
    using (
        auth.uid() = user_id
        or exists (
            select 1
            from public.friend f
            where f.user_id = auth.uid()
              and f.friend_id = store.user_id
        )
    );

create policy "store: insert own rows"
    on public.store for insert
    with check (auth.uid() = user_id);

create policy "store: update own rows"
    on public.store for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

create policy "store: delete own rows"
    on public.store for delete
    using (auth.uid() = user_id);

-- =========================================
-- image
-- =========================================
create table if not exists public.image (
    id uuid primary key default gen_random_uuid(),
    store_id uuid not null references public.store (id) on delete cascade,
    image text not null, -- record-images バケット内のオブジェクトパス
    created_at timestamptz not null default now()
);

create index if not exists image_store_id_idx on public.image (store_id);

alter table public.image enable row level security;

create policy "image: select own or friend's rows"
    on public.image for select
    using (
        exists (
            select 1
            from public.store s
            where s.id = image.store_id
              and (
                  s.user_id = auth.uid()
                  or exists (
                      select 1
                      from public.friend f
                      where f.user_id = auth.uid()
                        and f.friend_id = s.user_id
                  )
              )
        )
    );

create policy "image: insert own rows"
    on public.image for insert
    with check (
        exists (
            select 1
            from public.store s
            where s.id = image.store_id
              and s.user_id = auth.uid()
        )
    );

create policy "image: update own rows"
    on public.image for update
    using (
        exists (
            select 1
            from public.store s
            where s.id = image.store_id
              and s.user_id = auth.uid()
        )
    )
    with check (
        exists (
            select 1
            from public.store s
            where s.id = image.store_id
              and s.user_id = auth.uid()
        )
    );

create policy "image: delete own rows"
    on public.image for delete
    using (
        exists (
            select 1
            from public.store s
            where s.id = image.store_id
              and s.user_id = auth.uid()
        )
    );
