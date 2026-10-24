-- 20261024150200_friend_search.sql の確認。migration 適用済みのテスト専用DBで管理者として実行する。
-- テストデータは最後にROLLBACKする。
begin;

insert into auth.users (id) values
    ('e0000000-0000-4000-8000-00000000000a'),
    ('e0000000-0000-4000-8000-00000000000b'),
    ('e0000000-0000-4000-8000-00000000000c'),
    ('e0000000-0000-4000-8000-00000000000d'),
    ('e0000000-0000-4000-8000-00000000000e');
insert into public."user" (id, user_name, name, profile_image) values
    ('e0000000-0000-4000-8000-00000000000a', 'search_a', 'Aさん', 'e0000000-0000-4000-8000-00000000000a/a.jpg'),
    ('e0000000-0000-4000-8000-00000000000b', 'search_b', 'Bさん', 'e0000000-0000-4000-8000-00000000000b/b.jpg'),
    ('e0000000-0000-4000-8000-00000000000c', 'search_c', 'Cさん', null),
    ('e0000000-0000-4000-8000-00000000000d', 'search_d', 'Dさん', null),
    ('e0000000-0000-4000-8000-00000000000e', 'search_e', 'Eさん', null);
-- A と B はフレンド。A→C は申請済み。D→A は申請が来ている。E は無関係。
insert into public.friend (user_id, friend_id) values
    ('e0000000-0000-4000-8000-00000000000a', 'e0000000-0000-4000-8000-00000000000b'),
    ('e0000000-0000-4000-8000-00000000000b', 'e0000000-0000-4000-8000-00000000000a');
insert into public.friend_request (requester_id, addressee_id) values
    ('e0000000-0000-4000-8000-00000000000a', 'e0000000-0000-4000-8000-00000000000c'),
    ('e0000000-0000-4000-8000-00000000000d', 'e0000000-0000-4000-8000-00000000000a');

insert into storage.buckets (id, name) values ('profile-images', 'profile-images') on conflict do nothing;
insert into storage.objects (bucket_id, name) values
    ('profile-images', 'e0000000-0000-4000-8000-00000000000a/a.jpg'),
    ('profile-images', 'e0000000-0000-4000-8000-00000000000b/b.jpg'),
    -- 差し替え前の古いアイコン（user.profile_image から外れたファイル）
    ('profile-images', 'e0000000-0000-4000-8000-00000000000b/old.jpg');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"e0000000-0000-4000-8000-00000000000a"}', true);

-- ---------- 関係ステータス ----------
do $$
begin
    assert (select relation = 'self' from public.search_user_by_user_name('search_a')), '自分自身がselfにならない';
    assert (select relation = 'friend' from public.search_user_by_user_name('search_b')), 'フレンドがfriendにならない';
    assert (select relation = 'requested' from public.search_user_by_user_name('search_c')), '申請済みがrequestedにならない';
    assert (select relation = 'incoming' from public.search_user_by_user_name('search_d')), '受信申請がincomingにならない';
    assert (select relation = 'none' from public.search_user_by_user_name('search_e')), '無関係がnoneにならない';

    -- 返す列は id・user_name・name・profile_image・relation のみ。
    assert (select id = 'e0000000-0000-4000-8000-00000000000b' and user_name = 'search_b' and name = 'Bさん'
                and profile_image = 'e0000000-0000-4000-8000-00000000000b/b.jpg'
            from public.search_user_by_user_name('search_b')), '検索結果の列が不正';
end $$;

-- ---------- 完全一致のみ ----------
do $$
begin
    -- 大文字・前後の空白は揃えて完全一致で比較する。
    assert (select count(*) = 1 from public.search_user_by_user_name('  SEARCH_E ')), '大文字・空白入りで見つからない';
    assert (select count(*) = 0 from public.search_user_by_user_name('search')), '部分一致で見つかった';
    assert (select count(*) = 0 from public.search_user_by_user_name('search_%')), 'ワイルドカードで見つかった';
    assert (select count(*) = 0 from public.search_user_by_user_name('')), '空文字で見つかった';
end $$;

-- ---------- 申請者の user 行の参照 ----------
do $$
begin
    -- 受信者 A は申請者 D の行を参照できる。
    assert (select count(*) = 1 from public."user" where id = 'e0000000-0000-4000-8000-00000000000d'), '受信者が申請者の行を参照できない';
    -- 申請先 C・無関係な E の行は見えない（user の RLS は広げていない）。
    assert (select count(*) = 0 from public."user" where id = 'e0000000-0000-4000-8000-00000000000c'), '申請先の行が見えた';
    assert (select count(*) = 0 from public."user" where id = 'e0000000-0000-4000-8000-00000000000e'), '無関係なユーザーの行が見えた';
end $$;

select set_config('request.jwt.claims', '{"sub":"e0000000-0000-4000-8000-00000000000c"}', true);
do $$
begin
    -- 受信者 C から申請者 A は見えるが、A の行の参照は申請がある間だけ。
    assert (select count(*) = 1 from public."user" where id = 'e0000000-0000-4000-8000-00000000000a'), '受信者Cが申請者Aを参照できない';
end $$;

-- ---------- profile-images ----------
select set_config('request.jwt.claims', '{"sub":"e0000000-0000-4000-8000-00000000000e"}', true);
do $$
begin
    -- 無関係な E でも、現在のアイコンのパスなら参照できる（パスは検索結果からしか分からない）。
    assert (select count(*) = 1 from storage.objects where name = 'e0000000-0000-4000-8000-00000000000a/a.jpg'),
        '現在のアイコンを参照できない';
    -- 差し替え前の古いアイコンは参照できない。
    assert (select count(*) = 0 from storage.objects where name = 'e0000000-0000-4000-8000-00000000000b/old.jpg'),
        '古いアイコンを参照できた';
end $$;

-- 申請が消えると、申請者の行は見えなくなる。
reset role;
delete from public.friend_request where requester_id = 'e0000000-0000-4000-8000-00000000000a';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"e0000000-0000-4000-8000-00000000000c"}', true);
do $$
begin
    assert (select count(*) = 0 from public."user" where id = 'e0000000-0000-4000-8000-00000000000a'), '申請削除後も申請者の行が見えた';
end $$;

-- 未ログインでは検索できない。
select set_config('request.jwt.claims', '', true);
do $$
begin
    begin
        perform public.search_user_by_user_name('search_a');
        raise exception '未ログインで検索できた';
    exception when sqlstate '28000' then null;
    end;
end $$;

reset role;
rollback;
