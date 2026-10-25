-- 20261024150000_user_name_default.sql の確認。friend_legacy_seed.sql の投入後に migration を適用した状態で実行する。
-- テストデータは最後にROLLBACKする。
begin;

-- 既存データの補完
do $$
begin
    assert (select count(*) = 0 from public."user" where user_name is null), 'NULLのuser_nameが残っている';
    assert (select count(*) = 0 from public."user" where user_name !~ '^[a-z0-9_]{3,20}$'), '形式違反のuser_nameが残っている';
    assert (select user_name ~ '^[a-z0-9]{10}$' from public."user" where id = 'c0000000-0000-4000-8000-000000000001'),
        'NULLの行が10桁の英小文字・数字で埋まっていない';
    assert (select user_name = 'valid_name' from public."user" where id = 'c0000000-0000-4000-8000-000000000003'),
        '形式を満たす既存値が変わった';
    assert (select user_name = 'legacy_upper' from public."user" where id = 'c0000000-0000-4000-8000-000000000004'),
        '小文字化で形式を満たす既存値が小文字に揃っていない';
    assert (select user_name ~ '^[a-z0-9]{10}$' from public."user" where id = 'c0000000-0000-4000-8000-000000000005'),
        '小文字化すると重複する値が採番し直されていない';
    assert (select user_name ~ '^[a-z0-9]{10}$' from public."user" where id = 'c0000000-0000-4000-8000-000000000006'),
        '形式違反の値が採番し直されていない';
end $$;

insert into auth.users (id) values
    ('c1000000-0000-4000-8000-000000000001'),
    ('c1000000-0000-4000-8000-000000000002');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"c1000000-0000-4000-8000-000000000001"}', true);

-- アプリ（AuthViewModel.createUserIfNeeded）と同じく user_name なしで登録すると自動採番される。
insert into public."user" (id, name) values (auth.uid(), '採番テスト')
on conflict (id) do nothing;
do $$
begin
    assert (select user_name ~ '^[a-z0-9]{10}$' from public."user" where id = auth.uid()),
        '新規登録時にuser_nameが自動設定されない';
end $$;

-- 2回目以降のログインと同じ upsert（重複は無視）では既存の user_name が変わらない。
select set_config('friend_test.generated', user_name, true) from public."user" where id = auth.uid();
insert into public."user" (id, name) values (auth.uid(), '上書きされない')
on conflict (id) do nothing;
do $$
begin
    assert (select user_name = current_setting('friend_test.generated') from public."user" where id = auth.uid()),
        '再ログイン時にuser_nameが変わった';
end $$;

-- 本人は変更でき、大文字は小文字に揃えて保存される。
update public."user" set user_name = 'My_Name_01' where id = auth.uid();
do $$
begin
    assert (select user_name = 'my_name_01' from public."user" where id = auth.uid()), '大文字が小文字に揃っていない';
end $$;

-- 形式違反・NULL・重複は拒否される。
do $$
begin
    begin
        update public."user" set user_name = 'ab' where id = auth.uid();
        raise exception '2文字のuser_nameを保存できた';
    exception when check_violation then null;
    end;
    begin
        update public."user" set user_name = 'with-hyphen' where id = auth.uid();
        raise exception '記号を含むuser_nameを保存できた';
    exception when check_violation then null;
    end;
    begin
        update public."user" set user_name = 'abcdefghijklmnopqrstu' where id = auth.uid();
        raise exception '21文字のuser_nameを保存できた';
    exception when check_violation then null;
    end;
    begin
        update public."user" set user_name = null where id = auth.uid();
        raise exception 'user_nameをNULLにできた';
    exception when not_null_violation then null;
    end;
    -- 他人の値（RLSで見えない行）との重複も一意制約で拒否される。
    begin
        update public."user" set user_name = 'VALID_NAME' where id = auth.uid();
        raise exception '他人と重複するuser_nameを保存できた';
    exception when unique_violation then null;
    end;
end $$;

-- 採番関数はクライアントから直接呼べない。
do $$
begin
    begin
        perform public.generate_user_name();
        raise exception 'generate_user_nameをクライアント権限で呼べた';
    exception when insufficient_privilege then null;
    end;
end $$;

-- 明示指定した user_name で登録する場合も小文字に揃う。
select set_config('request.jwt.claims', '{"sub":"c1000000-0000-4000-8000-000000000002"}', true);
insert into public."user" (id, user_name) values (auth.uid(), 'Explicit_Name');
do $$
begin
    assert (select user_name = 'explicit_name' from public."user" where id = auth.uid()), '登録時の大文字が小文字に揃っていない';
end $$;

reset role;
rollback;
