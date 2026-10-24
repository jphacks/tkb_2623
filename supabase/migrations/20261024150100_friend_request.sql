-- Supabaseダッシュボード > SQL Editor に貼り付けて実行してください。
-- 20261024150000_user_name_default.sql を先に実行しておくこと。
--
-- フレンド申請・承認の仕組みを追加する。
--
-- 方針:
--   - friend テーブルのスキーマは変えない。相互フレンドは A→B と B→A の2行で表す。
--     既存の friend 行（片方向のものを含む）はそのまま残す。
--   - friend への直接 insert は禁止し、行の作成は承認系の関数（SECURITY DEFINER）経由のみにする。
--   - friend_request は承認待ち（pending）の申請だけを持つ。承認・拒否・取り消しで行を削除する。
--   - 申請しようとした相手から既に申請が来ていれば、その場で承認扱い（相互フレンド成立）にする。
--     これは同じトランザクション内で判定する必要があるため、申請は send_friend_request() で行う。
--
-- 関数が返すエラー（SQLSTATE）。アプリ側（FriendRepository）でメッセージに変換する。
--   28000: 未ログイン
--   GSF01: 自分自身には申請できない
--   GSF02: 既にフレンド
--   GSF04: 承認しようとした申請が存在しない（取り消し済み・処理済み）
--   GSF05: 申請先のユーザーが存在しない

-- =========================================
-- friend_request
-- =========================================
create table if not exists public.friend_request (
    requester_id uuid not null references public."user" (id) on delete cascade,
    addressee_id uuid not null references public."user" (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (requester_id, addressee_id),
    check (requester_id <> addressee_id)
);

-- 受け取った申請の一覧・件数は addressee_id で引く。
create index if not exists friend_request_addressee_id_idx on public.friend_request (addressee_id);

alter table public.friend_request enable row level security;

create policy "friend_request: select own requests"
    on public.friend_request for select
    using (auth.uid() = requester_id or auth.uid() = addressee_id);

-- アプリは send_friend_request() を使う。直接 insert する場合も、既にフレンドの相手や
-- 相手から申請が来ている（承認すべき）相手への申請は作らせない。
create policy "friend_request: insert as requester"
    on public.friend_request for insert
    with check (
        auth.uid() = requester_id
        and not exists (
            select 1
            from public.friend f
            where f.user_id = requester_id
              and f.friend_id = addressee_id
        )
        and not exists (
            select 1
            from public.friend_request r
            where r.requester_id = friend_request.addressee_id
              and r.addressee_id = friend_request.requester_id
        )
    );

-- 申請者は取り消し、受信者は拒否として削除できる。
create policy "friend_request: delete by requester or addressee"
    on public.friend_request for delete
    using (auth.uid() = requester_id or auth.uid() = addressee_id);

-- =========================================
-- friend: 直接 insert を禁止する
-- =========================================
drop policy if exists "friend: insert own edges" on public.friend;

-- =========================================
-- 関数
-- =========================================
-- 2人の間の申請を消し、friend を両方向に作る。呼び出し元で権限確認・ロックを済ませてから呼ぶ。
create or replace function public.establish_friendship(p_user_a uuid, p_user_b uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    delete from public.friend_request
    where (requester_id = p_user_a and addressee_id = p_user_b)
       or (requester_id = p_user_b and addressee_id = p_user_a);

    insert into public.friend (user_id, friend_id)
    values (p_user_a, p_user_b), (p_user_b, p_user_a)
    on conflict do nothing;
end;
$$;

-- 権限確認を持たない内部用の関数なので、クライアントからは呼ばせない。
revoke all on function public.establish_friendship(uuid, uuid) from public, anon, authenticated;

-- 同じ2人の組に対する申請・承認を直列化する（互いに同時に申請した場合の二重申請を防ぐ）。
create or replace function public.lock_friend_pair(p_user_a uuid, p_user_b uuid)
returns void
language sql
security definer
set search_path = ''
as $$
    select pg_advisory_xact_lock(
        hashtextextended(least(p_user_a::text, p_user_b::text) || ':' || greatest(p_user_a::text, p_user_b::text), 0)
    );
$$;

revoke all on function public.lock_friend_pair(uuid, uuid) from public, anon, authenticated;

-- ログイン中ユーザーから p_addressee_id へフレンド申請する。
-- 戻り値: 'requested'（申請した。既に申請済みの場合も同じ）/ 'accepted'（相手からの申請を承認し、フレンドになった）
create or replace function public.send_friend_request(p_addressee_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
    me uuid := auth.uid();
begin
    if me is null then
        raise exception 'not authenticated' using errcode = '28000';
    end if;
    if p_addressee_id = me then
        raise exception 'cannot send a friend request to yourself' using errcode = 'GSF01';
    end if;
    if not exists (select 1 from public."user" u where u.id = p_addressee_id) then
        raise exception 'user not found' using errcode = 'GSF05';
    end if;

    perform public.lock_friend_pair(me, p_addressee_id);

    if exists (select 1 from public.friend f where f.user_id = me and f.friend_id = p_addressee_id) then
        raise exception 'already friends' using errcode = 'GSF02';
    end if;

    if exists (
        select 1 from public.friend_request r
        where r.requester_id = p_addressee_id and r.addressee_id = me
    ) then
        perform public.establish_friendship(me, p_addressee_id);
        return 'accepted';
    end if;

    insert into public.friend_request (requester_id, addressee_id)
    values (me, p_addressee_id)
    on conflict do nothing;
    return 'requested';
end;
$$;

revoke all on function public.send_friend_request(uuid) from public, anon;
grant execute on function public.send_friend_request(uuid) to authenticated;

-- p_requester_id から自分（ログイン中ユーザー）宛ての申請を承認する。
-- 申請の削除と friend の両方向 insert を1トランザクションで行う。
create or replace function public.accept_friend_request(p_requester_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    me uuid := auth.uid();
begin
    if me is null then
        raise exception 'not authenticated' using errcode = '28000';
    end if;

    perform public.lock_friend_pair(me, p_requester_id);

    -- 呼び出し者が受信者（addressee）である申請だけを承認できる。
    if not exists (
        select 1 from public.friend_request r
        where r.requester_id = p_requester_id and r.addressee_id = me
    ) then
        raise exception 'friend request not found' using errcode = 'GSF04';
    end if;

    perform public.establish_friendship(me, p_requester_id);
end;
$$;

revoke all on function public.accept_friend_request(uuid) from public, anon;
grant execute on function public.accept_friend_request(uuid) to authenticated;
