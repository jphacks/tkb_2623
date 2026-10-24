-- マップ画面の手動確認用シードデータ。自動テストではなく、COMMITして行を残す。
-- RLSを通さない管理者(postgres / service_role)として実行する。本番DBでは実行しないこと。
--
-- psqlのメタコマンド(\set / \if)を使わないため、次のいずれでもそのまま実行できる:
--   - Supabaseダッシュボード > SQL Editor に貼り付け
--   - supabase db query --linked -f supabase/tests/seed_store.sql
--   - psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/seed_store.sql
--
-- 実行前に、下の2つのUUIDを置き換える。どちらも public."user" に行があるユーザーのID
-- (未登録ならassertで中断する)。確認用クエリ:
--   select id, email from public."user" order by created_at;
--
-- owner  : 自分の店舗として表示したいユーザー
-- friend : フレンド(フォロー中の相手)の店舗として表示したいユーザー
--          1ユーザーだけで確認する場合は、ownerと同じUUIDを入れてよい。
--          その場合フレンド用の行はownerの店舗になり、フォロー関係は作られない。
--
-- 片付けは末尾の「削除」コメントを参照(google_place_idの接頭辞 seed- で絞り込める)。

begin;

-- 第3引数をfalseにしてセッション有効にする。trueだとトランザクション終了で破棄され、
-- commit後の確認クエリからcurrent_settingが読めなくなる。
select set_config('seed_store.owner_id', 'REPLACE_WITH_OWNER_UUID', false);
select set_config('seed_store.friend_id', 'REPLACE_WITH_FRIEND_UUID', false);

do $$
declare
    owner_id uuid := current_setting('seed_store.owner_id')::uuid;
    friend_id uuid := current_setting('seed_store.friend_id')::uuid;
begin
    -- store.user_idはpublic."user".idを参照するため、プロフィール行が必要。
    assert (select count(*) from public."user" where id in (owner_id, friend_id))
        = (select count(distinct x) from unnest(array[owner_id, friend_id]) as x),
        'public."user"に対象ユーザーの行がありません。先にアプリでログインしてください。';

    -- 文京区・谷根千の徒歩圏。全ピンが1画面に収まる範囲に置く。
    -- categoryはPlaceCategoryClassifier.categoryRulesの名称をそのまま使う。
    -- google_place_id 'seed-shared-ramen' はowner・friendの両方に入れて、
    -- 「自分とフレンドの両方が登録した店舗」のピンバッジを確認できるようにする。
    insert into public.store
        (user_id, name, category, reputation, google_place_id, memo, repeat_num, latitude, longitude)
    values
        (owner_id, '喫茶 ゆうやけ', 'カフェ・喫茶', 4.5,
            'seed-cafe-yuyake', '夕やけだんだん側。昼は満席になりやすい。', 3, 35.7205, 139.7666),
        (owner_id, 'よみせ通り食堂', '和食', 3.0,
            'seed-washoku-yomise', '日替わり定食が安い。', 1, 35.7238, 139.7645),
        -- reputationがNULLの行。任意項目の表示確認用。
        (owner_id, '中華そば 根津', 'ラーメン・麺類', null,
            'seed-shared-ramen', 'まだ評価を付けていない店。', 2, 35.7207, 139.7659),
        -- memoがNULLの行。
        (owner_id, 'ベーカリー千駄木', 'パン', 4.0,
            'seed-bakery-sendagi', null, 1, 35.7252, 139.7622),
        (friend_id, '立ち飲み 参道', '居酒屋・バー', 5.0,
            'seed-izakaya-sando', '参道沿い。17時開店。', 5, 35.7188, 139.7638),
        (friend_id, '甘味処 やなか', 'スイーツ', 2.5,
            'seed-sweets-yanaka', 'テイクアウトのみ。', 0, 35.7223, 139.7679),
        (friend_id, '中華そば 根津', 'ラーメン・麺類', 4.0,
            'seed-shared-ramen', 'フレンドも行っている店。', 1, 35.7207, 139.7659),
        (friend_id, '焼肉 本郷', '焼肉・肉料理', 3.5,
            'seed-yakiniku-hongo', '昼のランチが狙い目。', 2, 35.7150, 139.7605);

    -- フレンドは片方向フォロー。双方から見えるように両向きに張る。
    -- 同じユーザーを指定した場合は自己フォローになるためスキップする(CHECK制約違反になる)。
    if owner_id <> friend_id then
        insert into public.friend (user_id, friend_id)
        values (owner_id, friend_id), (friend_id, owner_id)
        on conflict do nothing;
    end if;
end $$;

do $$
begin
    assert (select count(*) from public.store where google_place_id like 'seed-%') = 8,
        'シードデータが8件登録されていません';
end $$;

commit;

select s.name, s.category, s.reputation, s.repeat_num, s.memo, s.latitude, s.longitude,
       case when s.user_id = current_setting('seed_store.owner_id')::uuid then 'owner' else 'friend' end as 所有
from public.store s
where s.google_place_id like 'seed-%'
order by 所有, s.name;

-- 削除(手動確認が済んだら実行する。実データには触らない):
--   delete from public.store where google_place_id like 'seed-%';
--   delete from public.friend
--   where (user_id, friend_id) in (
--       ('<owner>', '<friend>'), ('<friend>', '<owner>')
--   );
