-- Supabaseダッシュボード > SQL Editor に貼り付けて実行してください。
-- タイムラインの記録（store）にコメントを付けられるようにする。
--
-- 方針:
--   - 閲覧・投稿できる範囲は store と同じ「本人 or フォロー中フレンドの記録」。
--   - image の insert ポリシー（店舗の所有者のみ）とは異なり、閲覧できる全員が投稿できる。
--   - 編集は無し（v1）。削除は投稿者本人のみ。

create table if not exists public.comment (
    id uuid primary key default gen_random_uuid(),
    store_id uuid not null references public.store (id) on delete cascade,
    user_id uuid not null references public."user" (id) on delete cascade,
    body text not null check (char_length(body) between 1 and 500),
    created_at timestamptz not null default now()
);

create index if not exists comment_store_id_idx on public.comment (store_id);

alter table public.comment enable row level security;

create policy "comment: select on own or friend's stores"
    on public.comment for select
    using (
        exists (
            select 1
            from public.store s
            where s.id = comment.store_id
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

create policy "comment: insert on own or friend's stores"
    on public.comment for insert
    with check (
        auth.uid() = user_id
        and exists (
            select 1
            from public.store s
            where s.id = comment.store_id
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

create policy "comment: delete own rows"
    on public.comment for delete
    using (auth.uid() = user_id);
