-- 既存schema.sqlを適用済みのテスト専用DBで管理者として実行する。
-- storeの定義・RLSは変更せず、テストデータは最後にROLLBACKする。
begin;

insert into auth.users (id, email) values
    ('a0240000-0000-4000-8000-000000000001', 'store-test-a@example.invalid'),
    ('a0240000-0000-4000-8000-000000000002', 'store-test-b@example.invalid');
insert into public."user" (id) values
    ('a0240000-0000-4000-8000-000000000001'),
    ('a0240000-0000-4000-8000-000000000002') on conflict do nothing;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a0240000-0000-4000-8000-000000000001","role":"authenticated"}', true);

insert into public.store (user_id, name, category, google_place_id, latitude, longitude, created_at)
values (auth.uid(), 'テスト店', 'カフェ・喫茶', 'store-test-place', 35, 139, '2001-01-01T00:00:00Z');
select set_config('store_test.record_id', id::text, true)
from public.store where google_place_id = 'store-test-place' and user_id = auth.uid();

-- アプリと同じくIDと所有者で更新対象を限定し、id・created_atは更新しない。
update public.store set name = '更新した店', reputation = null, memo = null, repeat_num = 7
where id = current_setting('store_test.record_id')::uuid and user_id = auth.uid();

do $$
begin
    assert (select created_at = '2001-01-01T00:00:00Z'::timestamptz and repeat_num = 7
        and name = '更新した店' and reputation is null and memo is null
        from public.store where id = current_setting('store_test.record_id')::uuid), '更新結果が不正';
end $$;

-- 既存storeの仕様を維持: カテゴリ・座標はNULL可、評価は小数可、初期回数は0。
insert into public.store (user_id, name, reputation) values (auth.uid(), '既存仕様の店', 4.5);
do $$
begin
    assert (select category is null and latitude is null and longitude is null
        and reputation = 4.5 and repeat_num = 0
        from public.store where name = '既存仕様の店' and user_id = auth.uid()), '既存仕様との不一致';
end $$;

select set_config('request.jwt.claims', '{"sub":"a0240000-0000-4000-8000-000000000002","role":"authenticated"}', true);
do $$
begin
    assert (select count(*) = 0 from public.store), '未フォローの他人の店舗が参照できた';
end $$;

-- フレンド共有も維持する。BがAをフォローするとAの店舗を参照できる。
insert into public.friend (user_id, friend_id)
values (auth.uid(), 'a0240000-0000-4000-8000-000000000001');
do $$
declare affected integer;
begin
    assert (select count(*) = 2 from public.store), 'フォロー相手の店舗が参照できない';
    update public.store set memo = '不正更新' where id = current_setting('store_test.record_id')::uuid;
    get diagnostics affected = row_count;
    assert affected = 0, 'フォロー相手の店舗が更新できた';
    begin
        insert into public.store (user_id, name)
        values ('a0240000-0000-4000-8000-000000000001', 'なりすまし');
        raise exception '他人のIDで登録できた';
    exception when insufficient_privilege then null;
    end;
end $$;

-- フレンドの行が見えても、所有者条件付きの検索は自分の行だけを返す。
insert into public.store (user_id, name, google_place_id)
values (auth.uid(), 'Bの記録', 'store-test-place');
do $$
begin
    assert (select count(*) = 1 from public.store
        where user_id = auth.uid() and google_place_id = 'store-test-place'), '所有者で限定できない';
end $$;

-- DBに一意制約を追加していないことを確認。重複時の扱いはSwiftで検証する。
insert into public.store (user_id, name, google_place_id)
values (auth.uid(), 'Bの重複記録', 'store-test-place');
do $$
begin
    assert (select count(*) = 2 from public.store
        where user_id = auth.uid() and google_place_id = 'store-test-place'), '既存の重複許容仕様との不一致';
end $$;

reset role;
rollback;
