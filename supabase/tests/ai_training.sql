-- Isolated database only; seed users and assert state machine/RLS behavior.
begin;
insert into auth.users(id) values ('a0000000-0000-0000-0000-000000000001');
insert into public."user"(id) values ('a0000000-0000-0000-0000-000000000001');
insert into public.store(id, user_id, name, reputation, category)
values ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'test', 4, '和食');
insert into public.image(store_id, image) values ('b0000000-0000-0000-0000-000000000001', 'photo.png');

do $$
declare j public.ai_training_jobs; j2 public.ai_training_jobs; ok boolean; v bigint; manifest jsonb;
begin
    if not exists (select 1 from public.ai_training_dirty_users where user_id = 'a0000000-0000-0000-0000-000000000001') then
        raise exception 'store/image changes did not mark dirty';
    end if;
    select * into j from public.ai_claim_training('a0000000-0000-0000-0000-000000000001');
    if j.id is null then raise exception 'claim failed'; end if;
    select * into j2 from public.ai_claim_training('a0000000-0000-0000-0000-000000000001', true);
    if j2.id is not null then raise exception 'live lease was stolen'; end if;
    select jsonb_agg(jsonb_build_object('place_id', 'p' || n)) into manifest from generate_series(1,6) n;
    if not public.ai_heartbeat_training(j.id, manifest) then raise exception 'snapshot failed'; end if;
    -- Change arrives during training and must survive completion.
    perform public.ai_mark_dirty(j.user_id);
    ok := public.ai_finish_training(j.id, 'succeeded', jsonb_build_object(
        'trained_records', 6, 'model_version', j.id::text, 'training_policy', 'personal-v2',
        'model_path', 'gs://test/models/model.joblib', 'mean_abs_error', 0.8));
    if not ok then raise exception 'publication failed'; end if;
    if not exists (select 1 from public.ai_model_status where model_version = j.id::text and cardinality(trained_store_ids) = 6) then
        raise exception 'publication metadata missing';
    end if;
    if not exists (select 1 from public.ai_training_dirty_users where version > processed_version) then
        raise exception 'change during training was lost';
    end if;
    if public.ai_finish_training(j.id, 'succeeded', '{}') then raise exception 'duplicate completion accepted'; end if;
    select * into j2 from public.ai_claim_training(j.user_id);
    -- Hard crash and lease expiry: new worker can claim, old worker cannot publish.
    update public.ai_training_dirty_users set lease_until = now() - interval '1 second' where user_id = j.user_id;
    select * into j from public.ai_claim_training(j.user_id);
    if j.id = j2.id or j.id is null then raise exception 'expired lease not reclaimed'; end if;
    if public.ai_finish_training(j2.id, 'succeeded', '{}') then raise exception 'stale worker published'; end if;
    if not public.ai_finish_training(j.id, 'failed', null, 'TimeoutError') then raise exception 'failure completion failed'; end if;
    if not exists (select 1 from public.ai_training_dirty_users where next_attempt_at > now()) then
        raise exception 'retry backoff not stored';
    end if;
    if not exists (select 1 from public.ai_model_status where record_count = 6) then
        raise exception 'failure removed last model';
    end if;
    perform public.ai_mark_dirty(j.user_id, true);
    select * into j from public.ai_claim_training(j.user_id);
    if not j.repair_requested then raise exception 'repair flag missing'; end if;
    -- A skipped job completes its source version without replacing the old model.
    if not public.ai_finish_training(j.id, 'skipped') then raise exception 'skip failed'; end if;
    perform public.ai_mark_dirty(j.user_id);
    select * into j from public.ai_claim_training(j.user_id);
    select jsonb_agg(jsonb_build_object('place_id', 'p' || n)) into manifest from generate_series(1,5) n;
    perform public.ai_heartbeat_training(j.id, manifest);
    begin
        perform public.ai_finish_training(j.id, 'succeeded', jsonb_build_object(
            'trained_records', 5, 'model_version', j.id::text, 'training_policy', 'personal-v2',
            'model_path', 'gs://test/bad-model.joblib', 'mean_abs_error', 0.8));
        raise exception 'five-record model was published';
    exception when others then
        if SQLERRM <> 'invalid publication' then raise; end if;
    end;
    perform public.ai_finish_training(j.id, 'failed', null, 'TooFewRecords');
    update public.ai_training_dirty_users set attempts = 5, next_attempt_at = now() where user_id = j.user_id;
    select * into j2 from public.ai_claim_training(j.user_id);
    if j2.id is not null then raise exception 'exhausted job retried automatically'; end if;
    perform public.ai_mark_dirty(j.user_id);
    select * into j2 from public.ai_claim_training(j.user_id);
    if j2.id is null then raise exception 'new data did not reset exhausted job'; end if;
    perform public.ai_finish_training(j2.id, 'skipped');
end;
$$;

set local role authenticated;
do $$
begin
    if has_function_privilege(current_user, 'public.ai_claim_training(uuid,boolean)', 'execute') then
        raise exception 'client can claim server jobs';
    end if;
    if has_table_privilege(current_user, 'public.ai_model_status', 'update') then
        raise exception 'client can publish model status';
    end if;
    if has_table_privilege(current_user, 'public.ai_training_jobs', 'select') then
        raise exception 'client can read internal job data';
    end if;
end;
$$;
reset role;
rollback;
