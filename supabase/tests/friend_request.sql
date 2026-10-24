-- 20261024150100_friend_request.sql の確認。migration 適用済みのテスト専用DBで管理者として実行する。
-- A・B・C の3ユーザーで申請・承認・拒否・取り消し・RLSを確認し、テストデータは最後にROLLBACKする。
begin;

insert into auth.users (id) values
    ('d0000000-0000-4000-8000-00000000000a'),
    ('d0000000-0000-4000-8000-00000000000b'),
    ('d0000000-0000-4000-8000-00000000000c');
insert into public."user" (id, user_name, name) values
    ('d0000000-0000-4000-8000-00000000000a', 'user_a', 'Aさん'),
    ('d0000000-0000-4000-8000-00000000000b', 'user_b', 'Bさん'),
    ('d0000000-0000-4000-8000-00000000000c', 'user_c', 'Cさん');

set local role authenticated;

-- ---------- A: 申請する ----------
select set_config('request.jwt.claims', '{"sub":"d0000000-0000-4000-8000-00000000000a"}', true);
do $$
begin
    assert public.send_friend_request('d0000000-0000-4000-8000-00000000000b') = 'requested', 'A→Bの申請結果が不正';
    -- 申請済みの相手にもう一度申請しても重複せず、同じ結果を返す。
    assert public.send_friend_request('d0000000-0000-4000-8000-00000000000b') = 'requested', '再申請の結果が不正';
    assert (select count(*) = 1 from public.friend_request), 'A→Bの申請が1件になっていない';

    -- 自分自身・存在しないユーザーへは申請できない。
    begin
        perform public.send_friend_request(auth.uid());
        raise exception '自分自身に申請できた';
    exception when sqlstate 'GSF01' then null;
    end;
    begin
        perform public.send_friend_request('d0000000-0000-4000-8000-0000000000ff');
        raise exception '存在しないユーザーに申請できた';
    exception when sqlstate 'GSF05' then null;
    end;

    -- friend への直接 insert はできない（作成は承認系の関数経由のみ）。
    begin
        insert into public.friend (user_id, friend_id) values (auth.uid(), 'd0000000-0000-4000-8000-00000000000c');
        raise exception 'friendに直接insertできた';
    exception when insufficient_privilege then null;
    end;

    -- 他人になりすました申請は作れない。
    begin
        insert into public.friend_request (requester_id, addressee_id)
        values ('d0000000-0000-4000-8000-00000000000c', 'd0000000-0000-4000-8000-00000000000b');
        raise exception '他人になりすまして申請できた';
    exception when insufficient_privilege then null;
    end;

    -- 申請者は自分宛てでない申請を承認できない。
    begin
        perform public.accept_friend_request('d0000000-0000-4000-8000-00000000000b');
        raise exception '受信者でないのに承認できた';
    exception when sqlstate 'GSF04' then null;
    end;

    -- 内部用の関数はクライアントから呼べない。
    begin
        perform public.establish_friendship(auth.uid(), 'd0000000-0000-4000-8000-00000000000c');
        raise exception 'establish_friendshipをクライアント権限で呼べた';
    exception when insufficient_privilege then null;
    end;
end $$;

-- ---------- C: 他人の申請は見えず、消せない ----------
select set_config('request.jwt.claims', '{"sub":"d0000000-0000-4000-8000-00000000000c"}', true);
do $$
declare affected integer;
begin
    assert (select count(*) = 0 from public.friend_request), '無関係なユーザーに申請が見えた';
    delete from public.friend_request;
    get diagnostics affected = row_count;
    assert affected = 0, '無関係なユーザーが申請を削除できた';
    begin
        perform public.accept_friend_request('d0000000-0000-4000-8000-00000000000a');
        raise exception '無関係なユーザーが承認できた';
    exception when sqlstate 'GSF04' then null;
    end;
end $$;

-- ---------- B: 受け取った申請を承認する ----------
select set_config('request.jwt.claims', '{"sub":"d0000000-0000-4000-8000-00000000000b"}', true);
do $$
begin
    assert (select count(*) = 1 from public.friend_request where addressee_id = auth.uid()), 'Bに受信申請が見えない';
    perform public.accept_friend_request('d0000000-0000-4000-8000-00000000000a');
    assert (select count(*) = 0 from public.friend_request), '承認後に申請が残っている';
    assert (select count(*) = 2 from public.friend
        where (user_id, friend_id) in (
            ('d0000000-0000-4000-8000-00000000000a'::uuid, 'd0000000-0000-4000-8000-00000000000b'::uuid),
            ('d0000000-0000-4000-8000-00000000000b'::uuid, 'd0000000-0000-4000-8000-00000000000a'::uuid))),
        '承認後にfriendが両方向に作られていない';

    -- 処理済みの申請はもう一度承認できない。
    begin
        perform public.accept_friend_request('d0000000-0000-4000-8000-00000000000a');
        raise exception '処理済みの申請を承認できた';
    exception when sqlstate 'GSF04' then null;
    end;

    -- 既にフレンドの相手には申請できない（関数・直接insertとも）。
    begin
        perform public.send_friend_request('d0000000-0000-4000-8000-00000000000a');
        raise exception 'フレンドに申請できた';
    exception when sqlstate 'GSF02' then null;
    end;
    begin
        insert into public.friend_request (requester_id, addressee_id)
        values (auth.uid(), 'd0000000-0000-4000-8000-00000000000a');
        raise exception 'フレンドへの申請を直接insertできた';
    exception when insufficient_privilege then null;
    end;
end $$;

-- ---------- 相手から申請が来ている相手に申請すると、その場で承認になる ----------
-- C→B を作ったあと、B が C に申請する。
select set_config('request.jwt.claims', '{"sub":"d0000000-0000-4000-8000-00000000000c"}', true);
do $$
begin
    assert public.send_friend_request('d0000000-0000-4000-8000-00000000000b') = 'requested', 'C→Bの申請結果が不正';
end $$;

select set_config('request.jwt.claims', '{"sub":"d0000000-0000-4000-8000-00000000000b"}', true);
do $$
begin
    -- 直接insertでは、承認すべき申請がある相手への逆向きの申請は作れない。
    begin
        insert into public.friend_request (requester_id, addressee_id)
        values (auth.uid(), 'd0000000-0000-4000-8000-00000000000c');
        raise exception '逆向きの申請を直接insertできた';
    exception when insufficient_privilege then null;
    end;

    assert public.send_friend_request('d0000000-0000-4000-8000-00000000000c') = 'accepted', 'B→Cが承認扱いにならない';
    assert (select count(*) = 0 from public.friend_request), '承認扱い後に申請が残っている';
    assert (select count(*) = 2 from public.friend
        where (user_id, friend_id) in (
            ('d0000000-0000-4000-8000-00000000000b'::uuid, 'd0000000-0000-4000-8000-00000000000c'::uuid),
            ('d0000000-0000-4000-8000-00000000000c'::uuid, 'd0000000-0000-4000-8000-00000000000b'::uuid))),
        '承認扱い後にfriendが両方向に作られていない';
end $$;

-- ---------- 取り消し・拒否 ----------
-- A→C を申請して A が取り消す。もう一度申請して C が拒否する。
select set_config('request.jwt.claims', '{"sub":"d0000000-0000-4000-8000-00000000000a"}', true);
do $$
declare affected integer;
begin
    perform public.send_friend_request('d0000000-0000-4000-8000-00000000000c');
    delete from public.friend_request
    where requester_id = auth.uid() and addressee_id = 'd0000000-0000-4000-8000-00000000000c';
    get diagnostics affected = row_count;
    assert affected = 1, '申請者が申請を取り消せない';
    perform public.send_friend_request('d0000000-0000-4000-8000-00000000000c');
end $$;

select set_config('request.jwt.claims', '{"sub":"d0000000-0000-4000-8000-00000000000c"}', true);
do $$
declare affected integer;
begin
    delete from public.friend_request
    where requester_id = 'd0000000-0000-4000-8000-00000000000a' and addressee_id = auth.uid();
    get diagnostics affected = row_count;
    assert affected = 1, '受信者が申請を拒否できない';
    assert not exists (select 1 from public.friend
        where user_id = auth.uid() and friend_id = 'd0000000-0000-4000-8000-00000000000a'), '拒否でfriendが作られた';
end $$;

-- 未ログインでは申請・承認できない。
select set_config('request.jwt.claims', '', true);
do $$
begin
    begin
        perform public.send_friend_request('d0000000-0000-4000-8000-00000000000a');
        raise exception '未ログインで申請できた';
    exception when sqlstate '28000' then null;
    end;
    begin
        perform public.accept_friend_request('d0000000-0000-4000-8000-00000000000a');
        raise exception '未ログインで承認できた';
    exception when sqlstate '28000' then null;
    end;
end $$;

reset role;
rollback;
