-- ブロック機能（blocked_user / block_user() RPC / 関連RLS）の検証。
-- 20261024150100_friend_request.sql 以降、friendへの直接insertは禁止されており、
-- フレンド成立は send_friend_request() / accept_friend_request() 経由のみになっている点に注意。
-- 管理者（postgres）として実行し、ユーザーの検証時のみauthenticatedへ切り替える。
-- 全テストデータは最後にROLLBACKする。
begin;

insert into auth.users(id) values
 ('a1000000-0000-4000-8000-000000000001'),
 ('a1000000-0000-4000-8000-000000000002'),
 ('a1000000-0000-4000-8000-000000000003');
insert into public."user"(id) select id from auth.users where id::text like 'a1000000%';

-- 事前状態: 1⇄2 の双方向フレンド（レガシー行として直接insertで再現）、1→3 の片方向フォロー。
insert into public.friend(user_id, friend_id) values
 ('a1000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000002'),
 ('a1000000-0000-4000-8000-000000000002','a1000000-0000-4000-8000-000000000001'),
 ('a1000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000003');

-- 無関係な保留中の申請（ユーザー3→ユーザー1）。ユーザー2のブロックで消えないことを確認する対照群。
insert into public.friend_request(requester_id, addressee_id) values
 ('a1000000-0000-4000-8000-000000000003','a1000000-0000-4000-8000-000000000001');

-- ユーザー2→ユーザー1への保留中の申請（ブロックで消えることを確認する対象）。
insert into public.friend_request(requester_id, addressee_id) values
 ('a1000000-0000-4000-8000-000000000002','a1000000-0000-4000-8000-000000000001');

insert into public.store(id, user_id, name) values
 ('a2000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','ユーザー1の店'),
 ('a2000000-0000-4000-8000-000000000002','a1000000-0000-4000-8000-000000000002','ユーザー2の店'),
 ('a2000000-0000-4000-8000-000000000003','a1000000-0000-4000-8000-000000000003','ユーザー3の店');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a1000000-0000-4000-8000-000000000001"}',true);

do $$
begin
    -- ブロック前は自分 + フォロー中2人の店（計3件）が見える。
    assert (select count(*)=3 from public.store), 'ブロック前は自分+フォロー2人の店が見えるはず';

    -- ユーザー1がユーザー2をブロックする。
    perform public.block_user('a1000000-0000-4000-8000-000000000002');

    -- ブロックした相手の店は見えなくなり、無関係な相手（ユーザー3）の店は見えたままになる。
    assert (select count(*)=2 from public.store), 'ブロック後はユーザー2の店が見えなくなるはず';
    assert not exists (
        select 1 from public.store where user_id = 'a1000000-0000-4000-8000-000000000002'
    ), 'ブロックした相手の店が見えている';
    assert exists (
        select 1 from public.store where user_id = 'a1000000-0000-4000-8000-000000000003'
    ), '無関係な相手の店が見えなくなっている';

    -- 双方向のフレンド関係が解除されている。
    assert not exists (
        select 1 from public.friend
        where (user_id = 'a1000000-0000-4000-8000-000000000001' and friend_id = 'a1000000-0000-4000-8000-000000000002')
           or (user_id = 'a1000000-0000-4000-8000-000000000002' and friend_id = 'a1000000-0000-4000-8000-000000000001')
    ), 'ブロックで双方向のフレンド関係が解除されていない';

    -- 無関係なフレンド関係（1→3）は残っている。
    assert exists (
        select 1 from public.friend
        where user_id = 'a1000000-0000-4000-8000-000000000001' and friend_id = 'a1000000-0000-4000-8000-000000000003'
    ), '無関係なフレンド関係まで解除されている';

    -- ユーザー2からユーザー1への保留中の申請も削除されている。
    assert not exists (
        select 1 from public.friend_request
        where requester_id = 'a1000000-0000-4000-8000-000000000002'
          and addressee_id = 'a1000000-0000-4000-8000-000000000001'
    ), 'ブロックで保留中の申請が削除されていない';

    -- 無関係な申請（3→1）は残っている。
    assert exists (
        select 1 from public.friend_request
        where requester_id = 'a1000000-0000-4000-8000-000000000003'
          and addressee_id = 'a1000000-0000-4000-8000-000000000001'
    ), '無関係な申請まで削除されている';

    -- blocked_userに登録され、名前参照用のuser選択ポリシーでブロック相手の名前も見える。
    assert exists (
        select 1 from public.blocked_user
        where blocker_id = 'a1000000-0000-4000-8000-000000000001'
          and blocked_id = 'a1000000-0000-4000-8000-000000000002'
    ), 'blocked_userに登録されていない';
    assert exists (
        select 1 from public."user" where id = 'a1000000-0000-4000-8000-000000000002'
    ), 'ブロック中ユーザー一覧表示に必要な、ブロック相手のuser行が見えない';

    -- ブロック中は自分からフレンド申請を送れない。
    begin
        perform public.send_friend_request('a1000000-0000-4000-8000-000000000002');
        assert false, 'ブロック中に自分からフレンド申請を送れてしまった';
    exception when sqlstate 'GSF03' then
        null; -- ブロック中であることを理由に拒否されることを期待する。
    end;

    -- block_user()は同じ相手に対して呼んでも安全（二重ブロックで失敗しない）。
    perform public.block_user('a1000000-0000-4000-8000-000000000002');
    assert (select count(*)=1 from public.blocked_user), '二重ブロックで行が増えてしまった';
end $$;

reset role;

-- ブロックされた側（ユーザー2）の視点でも、フレンド申請不可・相手の店が見えないことを確認する。
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a1000000-0000-4000-8000-000000000002"}',true);

do $$
begin
    assert not exists (
        select 1 from public.store where user_id = 'a1000000-0000-4000-8000-000000000001'
    ), 'ブロックされた側から、ブロックした側の店が見えている';

    begin
        perform public.send_friend_request('a1000000-0000-4000-8000-000000000001');
        assert false, 'ブロック中に相手側からフレンド申請を送れてしまった';
    exception when sqlstate 'GSF03' then
        null;
    end;

    -- ブロックされた側からは、ブロックした側（1）のuser行もblocked_user行も見えない。
    assert not exists (
        select 1 from public."user" where id = 'a1000000-0000-4000-8000-000000000001'
    ), 'ブロックされた側からブロックした側のuser行が見えている';
    assert not exists (
        select 1 from public.blocked_user
        where blocker_id = 'a1000000-0000-4000-8000-000000000001'
    ), 'ブロックされた側から相手のblocked_user行が見えている';
end $$;

reset role;

-- 解除: ブロックした側（1）が自分の行を削除できる。
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a1000000-0000-4000-8000-000000000001"}',true);

do $$
begin
    delete from public.blocked_user
    where blocker_id = 'a1000000-0000-4000-8000-000000000001'
      and blocked_id = 'a1000000-0000-4000-8000-000000000002';
    assert (select count(*)=0 from public.blocked_user), 'ブロック解除後も行が残っている';

    -- 解除後はフレンド申請を送り直せる（ブロック関係が無ければ拒否されない）。
    assert public.send_friend_request('a1000000-0000-4000-8000-000000000002') = 'requested',
        'ブロック解除後にフレンド申請を送れない';
    assert exists (
        select 1 from public.friend_request
        where requester_id = 'a1000000-0000-4000-8000-000000000001'
          and addressee_id = 'a1000000-0000-4000-8000-000000000002'
    ), 'ブロック解除後の申請が保存されていない';
end $$;

reset role;

-- ユーザー2が承認し、フレンドとして成立することを確認する。
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a1000000-0000-4000-8000-000000000002"}',true);

do $$
begin
    perform public.accept_friend_request('a1000000-0000-4000-8000-000000000001');
    assert exists (
        select 1 from public.friend
        where user_id = 'a1000000-0000-4000-8000-000000000001' and friend_id = 'a1000000-0000-4000-8000-000000000002'
    ), 'ブロック解除後に承認してもフレンドが成立していない（1→2）';
    assert exists (
        select 1 from public.friend
        where user_id = 'a1000000-0000-4000-8000-000000000002' and friend_id = 'a1000000-0000-4000-8000-000000000001'
    ), 'ブロック解除後に承認してもフレンドが成立していない（2→1）';
end $$;

reset role;
rollback;
