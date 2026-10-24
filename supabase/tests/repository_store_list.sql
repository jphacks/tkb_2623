begin;
insert into auth.users(id) values
 ('a1000000-0000-4000-8000-000000000001'), ('a1000000-0000-4000-8000-000000000002');
insert into public."user"(id) select id from auth.users where id::text like 'a1000000%';
insert into public.store(id,user_id,name,created_at) values
 ('a2000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','古い店','2025-01-01Z'),
 ('a2000000-0000-4000-8000-000000000003','a1000000-0000-4000-8000-000000000001','新しい店B','2025-02-01Z'),
 ('a2000000-0000-4000-8000-000000000002','a1000000-0000-4000-8000-000000000001','新しい店A','2025-02-01Z'),
 ('a2000000-0000-4000-8000-000000000004','a1000000-0000-4000-8000-000000000002','フレンドの店','2025-03-01Z');
insert into public.friend(user_id,friend_id) values
 ('a1000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000002');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a1000000-0000-4000-8000-000000000001"}',true);
do $$
declare names text[];
begin
 assert (select count(*)=4 from public.store), 'フレンドの行が見える前提';
 select array_agg(name order by created_at desc,id asc) into names from public.store where user_id=auth.uid();
 assert names=array['新しい店A','新しい店B','古い店'], '所有者フィルター・並び順が不正';
 assert (select count(*)=3 from public.store where user_id=auth.uid() and latitude is null), 'NULL座標の行も一覧に残す';
end $$;
reset role;
rollback;
