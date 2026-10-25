-- Supabaseダッシュボード > SQL Editor に貼り付けて実行してください。
-- タイムラインの記録（store）に「いいね」を付けられるようにする。
--
-- 方針:
--   - comment と同じく、閲覧・いいねできる範囲は store と同じ「本人 or フォロー中フレンドの記録」。
--   - 1ユーザー1店舗につき1件まで。主キー(store_id, user_id)で一意制約を兼ねる。
--   - 編集は無く、いいね・取り消し（insert/delete）のトグルだけ。

create table if not exists public.store_like (
    store_id uuid not null references public.store (id) on delete cascade,
    user_id uuid not null references public."user" (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (store_id, user_id)
);

create index if not exists store_like_store_id_idx on public.store_like (store_id);

alter table public.store_like enable row level security;

create policy "store_like: select on own or friend's stores"
    on public.store_like for select
    using (
        exists (
            select 1
            from public.store s
            where s.id = store_like.store_id
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

create policy "store_like: insert on own or friend's stores"
    on public.store_like for insert
    with check (
        auth.uid() = user_id
        and exists (
            select 1
            from public.store s
            where s.id = store_like.store_id
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

create policy "store_like: delete own rows"
    on public.store_like for delete
    using (auth.uid() = user_id);
