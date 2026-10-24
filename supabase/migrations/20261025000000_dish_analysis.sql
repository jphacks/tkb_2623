-- 料理写真の特徴抽出結果（1写真 = 1行）を保存する dish_analysis テーブル。
-- 抽出は Edge Function（service role）が行い、アプリからは参照のみ。
--
-- result（jsonb）の形（写真の主役の料理1つを記述する）:
--   {
--     "category": "...", "format": "...", "lineage": "...",
--     "parts": { ...カテゴリ（和食は形式）ごとに形が異なる... },
--     "common": { ...全カテゴリ共通の属性... },
--     "caption": "..."
--   }
--   項目は functions/analyze-dish/vocab/v1.ts で定義する。写真から判断できない項目は null。
--
-- category は store.category（登録画面でユーザーが選んだカテゴリ）をそのまま使う。
-- category / format / lineage は result と同じ値を列にも持つ（検索・集計用）。

create table if not exists public.dish_analysis (
    id uuid primary key default gen_random_uuid(),
    image_id uuid not null unique references public.image (id) on delete cascade,
    -- store_id / user_id はトリガーで image から自動設定する（呼び出し側の指定は上書き）。
    store_id uuid not null references public.store (id) on delete cascade,
    user_id uuid not null references public."user" (id) on delete cascade,
    status text not null default 'pending' check (status in ('pending', 'done', 'failed')),
    category text,
    format text,
    lineage text,
    result jsonb check (result is null or jsonb_typeof(result) = 'object'),
    error text,
    schema_version text not null, -- 語彙・スキーマのバージョン（例: v1）
    model text, -- 抽出に使ったモデルID
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (status <> 'done' or result is not null)
);

create index if not exists dish_analysis_user_id_idx on public.dish_analysis (user_id);
create index if not exists dish_analysis_store_id_idx on public.dish_analysis (store_id);
create index if not exists dish_analysis_category_idx on public.dish_analysis (category);

-- image → store から所有者を引いて設定し、image と矛盾した store_id / user_id を保存させない。
create or replace function public.set_dish_analysis_owner()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    select s.id, s.user_id
      into new.store_id, new.user_id
      from public.image i
      join public.store s on s.id = i.store_id
     where i.id = new.image_id;

    if new.store_id is null then
        raise exception 'image % not found', new.image_id;
    end if;

    new.updated_at := now();
    return new;
end;
$$;

create trigger dish_analysis_set_owner
    before insert or update on public.dish_analysis
    for each row execute function public.set_dish_analysis_owner();

alter table public.dish_analysis enable row level security;

-- 参照は image / store と同じ方針（自分の行と、フォロー中フレンドの行）。
create policy "dish_analysis: select own or friend's rows"
    on public.dish_analysis for select
    using (
        auth.uid() = user_id
        or exists (
            select 1
            from public.friend f
            where f.user_id = auth.uid()
              and f.friend_id = dish_analysis.user_id
        )
    );

-- insert / update / delete のポリシーは作らない。
-- 書き込みは RLS を迂回する service role（Edge Function）のみ。行の削除は image の削除に連動する。
