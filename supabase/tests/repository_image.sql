begin;
insert into auth.users(id) values
 ('b1000000-0000-4000-8000-000000000001'), ('b1000000-0000-4000-8000-000000000002');
insert into public."user"(id) select id from auth.users where id::text like 'b1000000%';
insert into public.store(id,user_id,name) values
 ('b2000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000001','画像テスト店');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"b1000000-0000-4000-8000-000000000001"}',true);
insert into public.image(id,store_id,image) values
 ('b3000000-0000-4000-8000-000000000001','b2000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000001/b2000000-0000-4000-8000-000000000001/test.jpg');
do $$ begin
 assert (select count(*)=1 from public.image), '本人が画像行を登録・取得できない';
end $$;
select set_config('request.jwt.claims','{"sub":"b1000000-0000-4000-8000-000000000002"}',true);
do $$ begin
 assert (select count(*)=0 from public.image), '未フォローで他人の画像が見えた';
end $$;
insert into public.friend(user_id,friend_id) values(auth.uid(),'b1000000-0000-4000-8000-000000000001');
do $$
declare affected integer;
begin
 assert (select count(*)=1 from public.image), 'フレンドが画像を閲覧できない';
 delete from public.image where id='b3000000-0000-4000-8000-000000000001';
 get diagnostics affected=row_count;
 assert affected=0, 'フレンドが画像を削除できた';
 update public.image set image='forged.jpg' where id='b3000000-0000-4000-8000-000000000001';
 get diagnostics affected=row_count;
 assert affected=0, 'フレンドが画像を書き換えられた';
 begin
  insert into public.image(store_id,image) values('b2000000-0000-4000-8000-000000000001','forged.jpg');
  raise exception '他人の店舗に画像行を追加できた';
 exception when insufficient_privilege then null;
 end;
end $$;
select set_config('request.jwt.claims','{"sub":"b1000000-0000-4000-8000-000000000001"}',true);
do $$
declare affected integer;
begin
 delete from public.image where id='b3000000-0000-4000-8000-000000000001';
 get diagnostics affected=row_count;
 assert affected=1, '本人が画像行を削除できない';
 assert (select count(*)=0 from public.image), '削除後の画像行が残っている';
end $$;
reset role;
rollback;
