-- AI v2: durable dirty users, fenced leases, immutable model generations.
-- Apply after 20261024100000_ai_backend_schema.sql. No network calls in triggers.
begin;

alter table public.ai_model_status
    add column model_version text,
    add column training_policy text,
    add column trained_store_ids text[] not null default '{}',
    add column successful_job_id uuid;

-- Clients only read public statistics. All publishing is server-only.
drop policy if exists "ai_model_status: insert own row" on public.ai_model_status;
drop policy if exists "ai_model_status: update own row" on public.ai_model_status;
drop policy if exists "ai_model_status: delete own row" on public.ai_model_status;
revoke insert, update, delete on public.ai_model_status from anon, authenticated;

create table public.ai_training_dirty_users (
    user_id uuid primary key references public."user"(id) on delete cascade,
    version bigint not null default 1,
    processed_version bigint not null default 0,
    repair_version bigint not null default 0,
    changed_at timestamptz not null default now(),
    attempts integer not null default 0,
    next_attempt_at timestamptz not null default now(),
    lease_token uuid,
    lease_until timestamptz
);

create table public.ai_training_jobs (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public."user"(id) on delete cascade,
    source_version bigint not null,
    repair_requested boolean not null default false,
    state text not null default 'running' check (state in ('running','succeeded','skipped','failed','expired')),
    snapshot jsonb not null default '[]',
    stats jsonb,
    error_code text,
    started_at timestamptz not null default now(),
    finished_at timestamptz
);
create index ai_training_jobs_user_started on public.ai_training_jobs(user_id, started_at desc);
create unique index ai_training_one_running on public.ai_training_jobs(user_id) where state = 'running';

alter table public.ai_training_dirty_users enable row level security;
alter table public.ai_training_jobs enable row level security;
revoke all on public.ai_training_dirty_users, public.ai_training_jobs from anon, authenticated;
grant all on public.ai_training_dirty_users, public.ai_training_jobs, public.ai_model_status to service_role;

create function public.ai_mark_dirty(p_user_id uuid, p_repair boolean default false)
returns void language plpgsql security definer set search_path = public as $$
begin
    -- Skip cascades deleting the owning user.
    if not exists (select 1 from public."user" where id = p_user_id) then return; end if;
    insert into public.ai_training_dirty_users(user_id, repair_version)
    values (p_user_id, case when p_repair then 1 else 0 end)
    on conflict (user_id) do update set
        version = ai_training_dirty_users.version + 1,
        repair_version = case when p_repair then ai_training_dirty_users.version + 1
                              else ai_training_dirty_users.repair_version end,
        changed_at = now(), attempts = 0, next_attempt_at = now();
end;
$$;

create function public.ai_record_changed()
returns trigger language plpgsql security definer set search_path = public as $$
declare owner_id uuid;
begin
    if TG_TABLE_NAME = 'store' then
        if TG_OP <> 'INSERT' then perform public.ai_mark_dirty(OLD.user_id); end if;
        if TG_OP <> 'DELETE' then perform public.ai_mark_dirty(NEW.user_id); end if;
    else
        if TG_OP <> 'INSERT' then
            select user_id into owner_id from public.store where id = OLD.store_id;
            perform public.ai_mark_dirty(owner_id);
        end if;
        if TG_OP <> 'DELETE' then
            select user_id into owner_id from public.store where id = NEW.store_id;
            perform public.ai_mark_dirty(owner_id);
        end if;
    end if;
    return null;
end;
$$;
create trigger ai_store_changed after insert or update or delete on public.store
    for each row execute function public.ai_record_changed();
create trigger ai_image_changed after insert or update or delete on public.image
    for each row execute function public.ai_record_changed();

-- force = developer requested publish; still cannot steal a live lease.
create function public.ai_claim_training(p_user_id uuid default null, p_force boolean default false)
returns setof public.ai_training_jobs language plpgsql security definer set search_path = public as $$
declare d public.ai_training_dirty_users; j public.ai_training_jobs;
begin
    update public.ai_training_jobs jx set state = 'expired', finished_at = now(), error_code = 'LeaseExpired'
        from public.ai_training_dirty_users dx
        where jx.id = dx.lease_token and jx.state = 'running' and dx.lease_until <= now() and dx.attempts >= 5;
    select * into d from public.ai_training_dirty_users
    where (p_user_id is null or user_id = p_user_id)
      and (lease_until is null or lease_until <= now())
      and (p_force or (version > processed_version and attempts < 5 and next_attempt_at <= now()))
    order by next_attempt_at, user_id for update skip locked limit 1;
    if not found then return; end if;
    update public.ai_training_jobs set state = 'expired', finished_at = now(), error_code = 'LeaseExpired'
        where user_id = d.user_id and state = 'running';
    insert into public.ai_training_jobs(user_id, source_version, repair_requested)
        values(d.user_id, d.version, p_force or d.repair_version > d.processed_version) returning * into j;
    update public.ai_training_dirty_users set lease_token = j.id,
        lease_until = now() + interval '5 minutes', attempts = attempts + 1 where user_id = d.user_id;
    return next j;
end;
$$;

create function public.ai_heartbeat_training(p_job_id uuid, p_snapshot jsonb default null)
returns boolean language plpgsql security definer set search_path = public as $$
declare uid uuid;
begin
    select user_id into uid from public.ai_training_jobs where id = p_job_id and state = 'running';
    update public.ai_training_dirty_users set lease_until = now() + interval '5 minutes'
        where user_id = uid and lease_token = p_job_id and lease_until > now();
    if not found then return false; end if;
    if p_snapshot is not null then
        update public.ai_training_jobs set snapshot = p_snapshot where id = p_job_id;
    end if;
    return true;
end;
$$;

create function public.ai_finish_training(p_job_id uuid, p_outcome text,
    p_stats jsonb default null, p_error_code text default null)
returns boolean language plpgsql security definer set search_path = public as $$
declare j public.ai_training_jobs; d public.ai_training_dirty_users; ids text[];
begin
    select * into j from public.ai_training_jobs where id = p_job_id;
    if not found then return false; end if;
    select * into d from public.ai_training_dirty_users where user_id = j.user_id for update;
    if d.lease_token is distinct from p_job_id or d.lease_until <= now() or j.state <> 'running' then
        return false;
    end if;
    if p_outcome not in ('succeeded','skipped','failed') then raise exception 'invalid outcome'; end if;
    if p_outcome = 'succeeded' then
        select array_agg(x->>'place_id') into ids from jsonb_array_elements(j.snapshot) x;
        if jsonb_array_length(j.snapshot) < 6 or coalesce((p_stats->>'trained_records')::int, -1) <> jsonb_array_length(j.snapshot)
           or p_stats->>'model_version' is distinct from p_job_id::text
           or p_stats->>'training_policy' is distinct from 'personal-v2'
           or p_stats->>'model_path' is null then
            raise exception 'invalid publication';
        end if;
        insert into public.ai_model_status(user_id, record_count, mean_abs_error, model_gcs_path,
            trained_at, model_version, training_policy, trained_store_ids, successful_job_id)
        values(j.user_id, cardinality(ids), (p_stats->>'mean_abs_error')::numeric,
            p_stats->>'model_path', now(), p_job_id::text, 'personal-v2', ids, p_job_id)
        on conflict(user_id) do update set record_count = excluded.record_count,
            mean_abs_error = excluded.mean_abs_error, model_gcs_path = excluded.model_gcs_path,
            trained_at = excluded.trained_at, model_version = excluded.model_version,
            training_policy = excluded.training_policy, trained_store_ids = excluded.trained_store_ids,
            successful_job_id = excluded.successful_job_id;
    end if;
    update public.ai_training_jobs set state = p_outcome, stats = p_stats,
        error_code = left(p_error_code, 100), finished_at = now() where id = p_job_id;
    update public.ai_training_dirty_users set
        processed_version = case when p_outcome = 'failed' then processed_version else j.source_version end,
        attempts = case when p_outcome = 'failed' then attempts else 0 end,
        next_attempt_at = case when p_outcome = 'failed' then now() + make_interval(secs => least(3600, 60 * (2 ^ least(attempts, 6)))::int)
                               else now() end,
        lease_token = null, lease_until = null where user_id = j.user_id;
    return true;
end;
$$;

-- One-time bootstrap also covers users who already have >=6 records.
insert into public.ai_training_dirty_users(user_id) select id from public."user";

revoke all on function public.ai_mark_dirty(uuid,boolean) from public, anon, authenticated;
revoke all on function public.ai_record_changed() from public, anon, authenticated;
revoke all on function public.ai_claim_training(uuid,boolean) from public, anon, authenticated;
revoke all on function public.ai_heartbeat_training(uuid,jsonb) from public, anon, authenticated;
revoke all on function public.ai_finish_training(uuid,text,jsonb,text) from public, anon, authenticated;
grant execute on function public.ai_mark_dirty(uuid,boolean), public.ai_claim_training(uuid,boolean),
    public.ai_heartbeat_training(uuid,jsonb), public.ai_finish_training(uuid,text,jsonb,text) to service_role;

commit;
