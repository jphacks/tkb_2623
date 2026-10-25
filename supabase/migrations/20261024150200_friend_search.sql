-- Supabaseダッシュボード > SQL Editor に貼り付けて実行してください。
-- 20261024150100_friend_request.sql を先に実行しておくこと。
--
-- フレンド追加画面のユーザー検索と、受け取った申請の一覧で相手の表示名・アイコンを出すための権限を追加する。
--
-- 方針:
--   - 検索は user_name の完全一致のみ。部分一致・一覧取得はできない。
--     user の RLS は広げず、SECURITY DEFINER の関数で必要な列だけを返す。
--   - 申請の受信者は、申請者の user 行（表示名・user_name・アイコン）を参照できる。
--   - profile-images は、user.profile_image に現在設定されているパスに限り、ログインユーザーなら署名付きURLを作れる。
--     パスは `<user_id>/<ランダムなUUID>.jpg` 形式で推測できず、他人のパスを知る手段は
--     検索関数（user_name の完全一致）・申請者の参照・フレンドの参照に限られるため、
--     実質的に「検索結果の相手・申請者・フレンド」のアイコンだけが見える。

-- =========================================
-- user_name 完全一致検索
-- =========================================
-- relation（ログイン中ユーザーから見た関係）:
--   'self'      自分自身
--   'friend'    既にフレンド（自分 → 相手の friend 行がある）
--   'requested' 自分が申請済み（承認待ち）
--   'incoming'  相手から申請が来ている
--   'none'      上記以外
create or replace function public.search_user_by_user_name(p_user_name text)
returns table (
    id uuid,
    user_name text,
    name text,
    profile_image text,
    relation text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    me uuid := auth.uid();
begin
    if me is null then
        raise exception 'not authenticated' using errcode = '28000';
    end if;

    return query
    select
        u.id,
        u.user_name,
        u.name,
        u.profile_image,
        case
            when u.id = me then 'self'
            when exists (
                select 1 from public.friend f where f.user_id = me and f.friend_id = u.id
            ) then 'friend'
            when exists (
                select 1 from public.friend_request r where r.requester_id = me and r.addressee_id = u.id
            ) then 'requested'
            when exists (
                select 1 from public.friend_request r where r.requester_id = u.id and r.addressee_id = me
            ) then 'incoming'
            else 'none'
        end
    from public."user" u
    -- user_name は小文字で保存しているため、入力も小文字に揃えて完全一致で比較する。
    where u.user_name = lower(btrim(p_user_name));
end;
$$;

revoke all on function public.search_user_by_user_name(text) from public, anon;
grant execute on function public.search_user_by_user_name(text) to authenticated;

-- =========================================
-- user: 申請の受信者は申請者の行を参照できる
-- =========================================
create policy "user: select requesters"
    on public."user" for select
    using (
        exists (
            select 1
            from public.friend_request r
            where r.addressee_id = auth.uid()
              and r.requester_id = "user".id
        )
    );

-- =========================================
-- profile-images: 現在のアイコンはパスを知っていれば参照できる
-- =========================================
-- user の RLS では他人の行が見えないため、ポリシーから SECURITY DEFINER の関数で判定する。
create or replace function public.is_current_profile_image(p_path text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (select 1 from public."user" u where u.profile_image = p_path);
$$;

-- Storage の参照ごとに評価されるため、profile_image で引けるようにする。
create index if not exists user_profile_image_idx on public."user" (profile_image);

revoke all on function public.is_current_profile_image(text) from public, anon;
grant execute on function public.is_current_profile_image(text) to authenticated;

create policy "profile-images: current icons can be viewed by signed-in users"
    on storage.objects for select
    to authenticated
    using (
        bucket_id = 'profile-images'
        and public.is_current_profile_image(name)
    );
