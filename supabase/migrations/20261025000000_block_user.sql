-- Supabaseダッシュボード > SQL Editor に貼り付けて実行してください。
-- 20261024150100_friend_request.sql を先に実行しておくこと
-- （friend の直接 insert が廃止され、send_friend_request()/establish_friendship() 経由に
--  なっているため、ブロック中の再フレンド化はそちらの関数側で防ぐ）。
--
-- ブロック機能: blocked_user テーブルと関連ポリシー・RPCを追加する。
--
-- 方針（2026-10-25 開発者と合意）:
--   - ブロックした相手の store / image は自分から見えなくなり、相手からも自分の
--     store / image が見えなくなる（双方向で非表示）。
--   - ブロック操作では、既存のフォロー関係（friend）・保留中のフレンド申請（friend_request）を
--     双方向で解除する。自分の行しか削除できない既存RLSでは相手側の行を消せないため、
--     SECURITY DEFINER の block_user() RPC内でまとめて行う。
--   - ブロック関係がある間は、どちらからも新たにフレンド申請・成立できない
--     （send_friend_request() / establish_friendship() にブロックチェックを追加）。
--   - ブロック中ユーザー一覧（プロフィール画面）に相手の名前を表示するため、
--     userテーブルに「自分がブロックした相手の行は参照可」のポリシーを追加する。
--   - 通報(Report)機能は対象外。ブロックの解除はクライアントから直接
--     blocked_user を削除するだけでよい（RLSの「自分の行」削除で十分なため、
--     unblock用のRPCは用意しない）。

-- =========================================
-- blocked_user（非対称に保存。blocker_id が blocked_id をブロックする）
-- =========================================
create table if not exists public.blocked_user (
    blocker_id uuid not null references public."user" (id) on delete cascade,
    blocked_id uuid not null references public."user" (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (blocker_id, blocked_id),
    check (blocker_id <> blocked_id)
);

create index if not exists blocked_user_blocked_id_idx on public.blocked_user (blocked_id);

alter table public.blocked_user enable row level security;

create policy "blocked_user: select own rows"
    on public.blocked_user for select
    using (auth.uid() = blocker_id);

create policy "blocked_user: insert own rows"
    on public.blocked_user for insert
    with check (auth.uid() = blocker_id);

create policy "blocked_user: delete own rows"
    on public.blocked_user for delete
    using (auth.uid() = blocker_id);

-- =========================================
-- user: ブロック中の相手の名前・アイコンを一覧表示できるようにする
-- =========================================
create policy "user: select blocked users"
    on public."user" for select
    using (
        exists (
            select 1
            from public.blocked_user b
            where b.blocker_id = auth.uid()
              and b.blocked_id = "user".id
        )
    );

-- =========================================
-- is_blocked_either_way: a・bのどちらかがもう一方をブロックしているか。
-- blocked_userのSELECT RLSは「自分がブロックした行」しか見せないため、
-- ブロックされた側からの判定（相手が自分をブロックしているか）はRLS越しには行えない。
-- SECURITY DEFINERでRLSを経由せずに判定し、各ポリシーから共通で使う。
-- authenticatedへEXECUTEを許可する（RPC経由でも直接呼べる）ため、呼び出し元が
-- 当事者（user_a/user_bのいずれか）でない場合は無関係な相手同士の関係を問い合わせても
-- 常にfalseを返す。これにより、ポリシー内部の意図しない用途以外には使えない。
-- =========================================
create or replace function public.is_blocked_either_way(user_a uuid, user_b uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
    select exists (
        select 1
        from public.blocked_user b
        where auth.uid() in (user_a, user_b)
          and (
              (b.blocker_id = user_a and b.blocked_id = user_b)
              or (b.blocker_id = user_b and b.blocked_id = user_a)
          )
    );
$$;

revoke execute on function public.is_blocked_either_way(uuid, uuid) from public;
grant execute on function public.is_blocked_either_way(uuid, uuid) to authenticated;

-- =========================================
-- friend: ブロック関係がある間は新たにフレンド申請・成立できない
-- friend への直接insertは20261024150100_friend_request.sqlで既に禁止されているため、
-- send_friend_request() / establish_friendship() の2関数にチェックを追加する
-- （元の実装はそのまま維持し、ブロック確認の分岐だけ追加するcreate or replace）。
-- =========================================
create or replace function public.establish_friendship(p_user_a uuid, p_user_b uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    if public.is_blocked_either_way(p_user_a, p_user_b) then
        raise exception 'blocked' using errcode = 'GSF03';
    end if;

    delete from public.friend_request
    where (requester_id = p_user_a and addressee_id = p_user_b)
       or (requester_id = p_user_b and addressee_id = p_user_a);

    insert into public.friend (user_id, friend_id)
    values (p_user_a, p_user_b), (p_user_b, p_user_a)
    on conflict do nothing;
end;
$$;

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
    if public.is_blocked_either_way(me, p_addressee_id) then
        raise exception 'blocked' using errcode = 'GSF03';
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

-- =========================================
-- store / image: ブロック関係がある相手の行は双方向で見えなくする
-- （friendの行はblock_user()で削除されるが、念のため直接のチェックも入れておく）
-- =========================================
drop policy "store: select own or friend's rows" on public.store;

create policy "store: select own or friend's rows"
    on public.store for select
    using (
        auth.uid() = user_id
        or (
            exists (
                select 1
                from public.friend f
                where f.user_id = auth.uid()
                  and f.friend_id = store.user_id
            )
            and not public.is_blocked_either_way(auth.uid(), store.user_id)
        )
    );

drop policy "image: select own or friend's rows" on public.image;

create policy "image: select own or friend's rows"
    on public.image for select
    using (
        exists (
            select 1
            from public.store s
            where s.id = image.store_id
              and (
                  s.user_id = auth.uid()
                  or (
                      exists (
                          select 1
                          from public.friend f
                          where f.user_id = auth.uid()
                            and f.friend_id = s.user_id
                      )
                      and not public.is_blocked_either_way(auth.uid(), s.user_id)
                  )
              )
        )
    );

-- =========================================
-- block_user: ブロックの登録、既存フォロー関係・保留中のフレンド申請の
-- 双方向解除をアトミックに行う
-- =========================================
create or replace function public.block_user(target_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if target_id = auth.uid() then
        raise exception 'cannot block yourself';
    end if;

    insert into public.blocked_user (blocker_id, blocked_id)
    values (auth.uid(), target_id)
    on conflict (blocker_id, blocked_id) do nothing;

    delete from public.friend
    where (user_id = auth.uid() and friend_id = target_id)
       or (user_id = target_id and friend_id = auth.uid());

    -- 保留中の申請も消す。残すと、ブロックした相手からの申請がブロック後も
    -- 申請一覧に残り続けてしまう（承認はestablish_friendship()のブロックチェックで
    -- 常に拒否されるが、見える状態そのものを残さない）。
    delete from public.friend_request
    where (requester_id = auth.uid() and addressee_id = target_id)
       or (requester_id = target_id and addressee_id = auth.uid());
end;
$$;

revoke execute on function public.block_user(uuid) from public;
grant execute on function public.block_user(uuid) to authenticated;
