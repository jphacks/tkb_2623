-- Supabaseダッシュボード > SQL Editor に貼り付けて実行してください。
-- フレンド申請の検索キーにする user.user_name を必須にする。
--
-- 方針:
--   - 形式は ^[a-z0-9_]{3,20}$（英小文字・数字・アンダースコアの3〜20文字）。
--   - 新規登録時に user_name が未指定なら、英小文字・数字10桁のランダム文字列を自動設定する
--     （AuthViewModel.createUserIfNeeded は user_name を送らないため、常にこちらで採番される）。
--   - 大文字で送られても小文字に揃えて保存する（アプリ側でも小文字化している）。
--   - 既存行の NULL・形式違反の値は、この migration で埋め直す。

-- =========================================
-- 採番
-- =========================================
-- 既存の user_name と衝突しない英小文字・数字10桁を返す。
-- RLSで他人の行が見えないと衝突を判定できないため SECURITY DEFINER にする。
create or replace function public.generate_user_name()
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
    alphabet constant text := 'abcdefghijklmnopqrstuvwxyz0123456789';
    candidate text;
begin
    loop
        select string_agg(substr(alphabet, 1 + floor(random() * 36)::int, 1), '')
        into candidate
        from generate_series(1, 10);

        exit when not exists (select 1 from public."user" u where u.user_name = candidate);
    end loop;
    return candidate;
end;
$$;

-- クライアントから直接呼ぶ用途はないため、トリガー・migration からのみ使う。
revoke all on function public.generate_user_name() from public, anon, authenticated;

create or replace function public.set_user_name_defaults()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if new.user_name is not null then
        new.user_name := lower(new.user_name);
    elsif tg_op = 'INSERT' then
        new.user_name := public.generate_user_name();
    end if;
    return new;
end;
$$;

revoke all on function public.set_user_name_defaults() from public, anon, authenticated;

drop trigger if exists user_set_user_name_defaults on public."user";
create trigger user_set_user_name_defaults
    before insert or update of user_name on public."user"
    for each row execute function public.set_user_name_defaults();

-- =========================================
-- 既存行の補完
-- =========================================
-- NULL・形式違反の行を1行ずつ埋める。小文字化だけで形式を満たし、他と重複しなければその値を使う。
-- 1行ずつ別の文で更新するので、直前に採番した値との衝突も generate_user_name() が検出できる。
do $$
declare
    target record;
    normalized text;
begin
    for target in
        select id, user_name
        from public."user"
        where user_name is null or user_name !~ '^[a-z0-9_]{3,20}$'
        order by created_at, id
    loop
        normalized := lower(target.user_name);
        if normalized is null
            or normalized !~ '^[a-z0-9_]{3,20}$'
            or exists (select 1 from public."user" u where u.user_name = normalized and u.id <> target.id)
        then
            normalized := public.generate_user_name();
        end if;
        update public."user" set user_name = normalized where id = target.id;
    end loop;
end;
$$;

-- =========================================
-- 制約
-- =========================================
alter table public."user"
    alter column user_name set not null;

alter table public."user"
    add constraint user_user_name_format check (user_name ~ '^[a-z0-9_]{3,20}$');
