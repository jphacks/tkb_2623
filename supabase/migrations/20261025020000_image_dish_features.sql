-- Supabaseダッシュボード > SQL Editor に貼り付けて実行してください。
-- 記録写真（image 行）ごとに、料理写真の特徴抽出結果を保存するカラムを追加する。
-- 抽出は Edge Function analyze-dish（service role）が行う。設計: supabase/DISH_ANALYSIS.md
--
-- dish_features（jsonb）の形:
--   {
--     "schema_version": "v1",           -- 語彙・スキーマのバージョン（functions/analyze-dish/vocab）
--     "model": "gemini-...",            -- 抽出に使ったモデルID
--     "features": {                     -- Gemini の出力（写真の主役の料理1つを記述する）
--       "category": "...", "format": "...", "lineage": "...",
--       "parts": { ...カテゴリ（和食は形式）ごとに形が異なる... },
--       "common": { ...全カテゴリ共通の属性... },
--       "caption": "..."
--     }
--   }
--   項目は functions/analyze-dish/vocab/v1.ts で定義する。写真から判断できない項目は null。
--
-- dish_features_status:
--   null    解析が始まっていない（Webhook が届いていない・このカラム追加前の写真）
--   pending 解析中
--   done    解析済み（dish_features が入っている）
--   failed  解析失敗（理由は Edge Function のログ）
--
-- 参照・削除は image の既存 RLS に従う（自分の行とフォロー中フレンドの行を参照できる）。

alter table public.image
    add column if not exists dish_features jsonb
        check (dish_features is null or jsonb_typeof(dish_features) = 'object'),
    add column if not exists dish_features_status text
        check (dish_features_status in ('pending', 'done', 'failed')),
    add constraint image_dish_features_done_check
        check (dish_features_status is distinct from 'done' or dish_features is not null);
