-- Supabaseダッシュボード > SQL Editor に貼り付けて実行してください。
--
-- 背景: comment の閲覧範囲は「store の投稿者 or 投稿者をフォロー中の自分」だが、
-- コメントできるのは「store を見られる誰でも」なので、同じ記録にコメントした
-- 2人が互いをフォローしているとは限らない。
-- 既存の user / profile-images の閲覧ポリシーは「自分が直接フォローしている相手」
-- だけを対象にしているため、直接フォローしていないコメント投稿者の名前・アイコンは
-- 取得できず、タイムラインのコメント欄で「名前未設定」・頭文字アイコンのままになる。
--
-- 対応: 自分が見られる記録にコメントしている相手なら、その user 行とプロフィール画像を
-- 参照できるポリシーを追加する。

create policy "user: select commenters on visible stores"
    on public."user" for select
    using (
        exists (
            select 1
            from public.comment c
            join public.store s on s.id = c.store_id
            where c.user_id = "user".id
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

create policy "profile-images: visible via comments on visible stores"
    on storage.objects for select
    using (
        bucket_id = 'profile-images'
        and exists (
            select 1
            from public.comment c
            join public.store s on s.id = c.store_id
            where c.user_id = ((storage.foldername(name))[1])::uuid
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
