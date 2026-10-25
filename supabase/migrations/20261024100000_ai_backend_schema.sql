-- Supabaseダッシュボード > SQL Editor に貼り付けて実行してください。
-- AIバックエンド(ユーザーごとのレコメンドモデル)のための追加スキーマ。
-- 要件定義: mogumap_clip_lgbm/REQUIREMENTS.md
--
-- 既存の schema.sql / storage_policies.sql が適用済みであることを前提とする。

-- =========================================
-- store: AI学習の特徴量に必要なPlaces情報のスナップショットを追加
-- =========================================
-- 店舗登録時にGoogle Places Details APIの結果を保存する想定。既存行はNULL許容
-- (AIバックエンド側はNULLの場合デフォルト値で補完する)。
alter table public.store
    add column if not exists google_rating numeric(2, 1) check (google_rating is null or (google_rating >= 0 and google_rating <= 5)),
    add column if not exists price_level smallint check (price_level is null or (price_level >= 1 and price_level <= 4)),
    add column if not exists review_count integer check (review_count is null or review_count >= 0);

-- =========================================
-- ai_model_status: ユーザーごとのAIモデルの学習状況
-- 育成ページ(「AIを育てる」タブ)がここを直接読み、登録件数・モデル性能を表示する。
-- =========================================
create table if not exists public.ai_model_status (
    user_id uuid primary key references public."user" (id) on delete cascade,
    record_count integer not null default 0,
    mean_abs_error numeric(3, 2),
    model_gcs_path text,
    trained_at timestamptz
);

alter table public.ai_model_status enable row level security;

-- store/imageと同じ方針: 自分の行は全操作可、フレンドの行は参照のみ。
create policy "ai_model_status: select own or friend's row"
    on public.ai_model_status for select
    using (
        auth.uid() = user_id
        or exists (
            select 1
            from public.friend f
            where f.user_id = auth.uid()
              and f.friend_id = ai_model_status.user_id
        )
    );

create policy "ai_model_status: insert own row"
    on public.ai_model_status for insert
    with check (auth.uid() = user_id);

create policy "ai_model_status: update own row"
    on public.ai_model_status for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

create policy "ai_model_status: delete own row"
    on public.ai_model_status for delete
    using (auth.uid() = user_id);

-- Edge Function(service role)がAIバックエンドの学習結果を書き込むための upsert 用。
-- RLSは上記の通りだが、service roleはRLSをバイパスするため追加ポリシーは不要。
