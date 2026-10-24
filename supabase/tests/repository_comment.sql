begin;
insert into auth.users(id) values
 ('c1000000-0000-4000-8000-000000000001'),
 ('c1000000-0000-4000-8000-000000000002'),
 ('c1000000-0000-4000-8000-000000000003');
insert into public."user"(id) select id from auth.users where id::text like 'c1000000%';
insert into public.store(id,user_id,name) values
 ('c2000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','コメントテスト店');

set local role authenticated;

-- 本人: 自分の記録にコメントできる
select set_config('request.jwt.claims','{"sub":"c1000000-0000-4000-8000-000000000001"}',true);
insert into public.comment(id,store_id,user_id,body) values
 ('c3000000-0000-4000-8000-000000000001','c2000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','本人のコメント');
do $$ begin
 assert (select count(*)=1 from public.comment), '本人がコメントを登録・取得できない';
end $$;

-- 無関係の第三者: 見えない・投稿できない
select set_config('request.jwt.claims','{"sub":"c1000000-0000-4000-8000-000000000003"}',true);
do $$ begin
 assert (select count(*)=0 from public.comment), '未フォローで他人のコメントが見えた';
 begin
  insert into public.comment(store_id,user_id,body) values('c2000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000003','なりすまし');
  raise exception '未フォローなのにコメントを投稿できた';
 exception when insufficient_privilege then null;
 end;
end $$;

-- フレンド: 閲覧・投稿できるが、他人のコメントの削除・更新はできない
select set_config('request.jwt.claims','{"sub":"c1000000-0000-4000-8000-000000000002"}',true);
insert into public.friend(user_id,friend_id) values(auth.uid(),'c1000000-0000-4000-8000-000000000001');
insert into public.comment(id,store_id,user_id,body) values
 ('c3000000-0000-4000-8000-000000000002','c2000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000002','フレンドのコメント');
do $$
declare affected integer;
begin
 assert (select count(*)=2 from public.comment), 'フレンドがコメントを閲覧・投稿できない';
 delete from public.comment where id='c3000000-0000-4000-8000-000000000001';
 get diagnostics affected=row_count;
 assert affected=0, 'フレンドが他人のコメントを削除できた';
 update public.comment set body='改変' where id='c3000000-0000-4000-8000-000000000001';
 get diagnostics affected=row_count;
 assert affected=0, 'フレンドが他人のコメントを更新できた';
end $$;

-- 本人: 自分のコメントだけ削除できる（更新ポリシーは無いので本人でも更新は不可）
select set_config('request.jwt.claims','{"sub":"c1000000-0000-4000-8000-000000000001"}',true);
do $$
declare affected integer;
begin
 update public.comment set body='改変' where id='c3000000-0000-4000-8000-000000000001';
 get diagnostics affected=row_count;
 assert affected=0, '更新ポリシーが無いはずなのに本人が更新できた';
 delete from public.comment where id='c3000000-0000-4000-8000-000000000002';
 get diagnostics affected=row_count;
 assert affected=0, '本人が他人（フレンド）のコメントを削除できた';
 delete from public.comment where id='c3000000-0000-4000-8000-000000000001';
 get diagnostics affected=row_count;
 assert affected=1, '本人が自分のコメントを削除できない';
 assert (select count(*)=1 from public.comment), '削除後のコメント件数が想定と違う';
end $$;

reset role;
rollback;
