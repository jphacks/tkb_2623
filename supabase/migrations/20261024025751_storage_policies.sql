-- Supabaseダッシュボード > SQL Editor に貼り付けて実行してください。
-- schema.sql を先に実行しておくこと（friend テーブルのJOINに使用する）。
--
-- record-images / profile-images の2バケットを作成し、
-- 「自分のファイルは全操作可、フレンド（自分がフォローしている相手）のファイルは参照のみ」
-- という schema.sql の store / image と同じ方針のポリシーを設定する。
--
-- 運用ルール（必須）:
--   アップロードするオブジェクトのパスは必ず先頭が所有者の user_id（auth.uid()のテキスト表現）
--   のフォルダになるようにする。
--     record-images:  <user_id>/<store_id>/<filename>
--     profile-images: <user_id>/<filename>
--   クライアント側は必ずこの形式でパスを組み立てること。

insert into storage.buckets (id, name, public)
values
    ('record-images', 'record-images', false),
    ('profile-images', 'profile-images', false)
on conflict (id) do nothing;

-- ---------- record-images ----------
create policy "record-images: owner full access"
    on storage.objects for all
    using (
        bucket_id = 'record-images'
        and (storage.foldername(name))[1] = auth.uid()::text
    )
    with check (
        bucket_id = 'record-images'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

create policy "record-images: friends can view"
    on storage.objects for select
    using (
        bucket_id = 'record-images'
        and exists (
            select 1
            from public.friend f
            where f.user_id = auth.uid()
              and f.friend_id = ((storage.foldername(name))[1])::uuid
        )
    );

-- ---------- profile-images ----------
create policy "profile-images: owner full access"
    on storage.objects for all
    using (
        bucket_id = 'profile-images'
        and (storage.foldername(name))[1] = auth.uid()::text
    )
    with check (
        bucket_id = 'profile-images'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

create policy "profile-images: friends can view"
    on storage.objects for select
    using (
        bucket_id = 'profile-images'
        and exists (
            select 1
            from public.friend f
            where f.user_id = auth.uid()
              and f.friend_id = ((storage.foldername(name))[1])::uuid
        )
    );
