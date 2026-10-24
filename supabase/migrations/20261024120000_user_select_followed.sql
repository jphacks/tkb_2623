-- Supabaseダッシュボード > SQL Editor に貼り付けて実行してください。
-- タイムラインでフレンドの名前を表示するため、
-- フォロー中のユーザー（friend.user_id = 自分）の user 行を参照できるようにする。
-- store / image と同じく、片方向フォローの相手だけが対象。

create policy "user: select followed users"
    on public."user" for select
    using (
        exists (
            select 1
            from public.friend f
            where f.user_id = auth.uid()
              and f.friend_id = "user".id
        )
    );
