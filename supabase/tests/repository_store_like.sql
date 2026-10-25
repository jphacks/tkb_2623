begin;
insert into auth.users(id) values
 ('d1000000-0000-4000-8000-000000000001'),
 ('d1000000-0000-4000-8000-000000000002'),
 ('d1000000-0000-4000-8000-000000000003');
insert into public."user"(id) select id from auth.users where id::text like 'd1000000%';
insert into public.store(id,user_id,name) values
 ('d2000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001','いいねテスト店');

set local role authenticated;

-- 本人: 自分の記録にいいねできる
select set_config('request.jwt.claims','{"sub":"d1000000-0000-4000-8000-000000000001"}',true);
insert into public.store_like(store_id,user_id) values
 ('d2000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001');
do $$ begin
 assert (select count(*)=1 from public.store_like), '本人がいいねを登録・取得できない';
 begin
  insert into public.store_like(store_id,user_id) values
   ('d2000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001');
  raise exception '同じユーザーが同じ店舗に二重にいいねできた';
 exception when unique_violation then null;
 end;
end $$;

-- 無関係の第三者: 見えない・いいねできない
select set_config('request.jwt.claims','{"sub":"d1000000-0000-4000-8000-000000000003"}',true);
do $$ begin
 assert (select count(*)=0 from public.store_like), '未フォローで他人のいいねが見えた';
 begin
  insert into public.store_like(store_id,user_id) values
   ('d2000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000003');
  raise exception '未フォローなのにいいねできた';
 exception when insufficient_privilege then null;
 end;
end $$;

-- フレンド: 閲覧・いいねできるが、他人のいいねは取り消せない
select set_config('request.jwt.claims','{"sub":"d1000000-0000-4000-8000-000000000002"}',true);
insert into public.friend(user_id,friend_id) values(auth.uid(),'d1000000-0000-4000-8000-000000000001');
insert into public.store_like(store_id,user_id) values
 ('d2000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000002');
do $$
declare affected integer;
begin
 assert (select count(*)=2 from public.store_like), 'フレンドがいいねを閲覧・登録できない';
 delete from public.store_like
  where store_id='d2000000-0000-4000-8000-000000000001' and user_id='d1000000-0000-4000-8000-000000000001';
 get diagnostics affected=row_count;
 assert affected=0, 'フレンドが他人のいいねを取り消せた';
end $$;

-- 本人: 自分のいいねだけ取り消せる
select set_config('request.jwt.claims','{"sub":"d1000000-0000-4000-8000-000000000001"}',true);
do $$
declare affected integer;
begin
 delete from public.store_like
  where store_id='d2000000-0000-4000-8000-000000000001' and user_id='d1000000-0000-4000-8000-000000000002';
 get diagnostics affected=row_count;
 assert affected=0, '本人が他人（フレンド）のいいねを取り消せた';
 delete from public.store_like
  where store_id='d2000000-0000-4000-8000-000000000001' and user_id='d1000000-0000-4000-8000-000000000001';
 get diagnostics affected=row_count;
 assert affected=1, '本人が自分のいいねを取り消せない';
 assert (select count(*)=1 from public.store_like), '取り消し後のいいね件数が想定と違う';
end $$;

reset role;
rollback;
