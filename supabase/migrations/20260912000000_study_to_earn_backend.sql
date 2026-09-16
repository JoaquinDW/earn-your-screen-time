create extension if not exists pgcrypto with schema extensions;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table public.study_configuration (
  id boolean primary key default true check (id),
  enabled boolean not null default true,
  entitlement_required boolean not null default true,
  entitlement_id text not null default 'Earn your Screen Time Pro' check (length(entitlement_id) between 1 and 255),
  questions_per_session smallint not null default 1 check (questions_per_session = 1),
  passing_score smallint not null default 1 check (passing_score between 1 and questions_per_session),
  reward_seconds integer not null default 900 check (reward_seconds between 1 and 3600),
  daily_cap_seconds integer not null default 1800 check (daily_cap_seconds >= reward_seconds and daily_cap_seconds <= 86400),
  session_ttl_seconds integer not null default 900 check (session_ttl_seconds between 60 and 3600),
  max_regenerations smallint not null default 1 check (max_regenerations between 0 and 1),
  source_text_min_length integer not null default 80 check (source_text_min_length between 1 and 1000),
  source_text_max_length integer not null default 12000 check (source_text_max_length between 1000 and 50000),
  confidence_threshold numeric(4, 3) not null default 0.700 check (confidence_threshold between 0 and 1),
  difficulty text not null default 'medium' check (difficulty in ('easy', 'medium', 'hard')),
  generation_instructions text not null default 'Use only facts explicitly supported by the supplied OCR source. Write one concise question with an objectively gradable answer. Do not reveal the answer in the question.',
  grading_instructions text not null default 'Accept semantically equivalent answers. Reject guesses that do not demonstrate the required knowledge.',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (source_text_min_length <= source_text_max_length)
);

insert into public.study_configuration (id) values (true);

create table public.study_sessions (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  client_request_id uuid not null,
  status text not null default 'active' check (status in ('active', 'passed', 'abandoned', 'expired')),
  source_text text check (source_text is null or length(source_text) between 1 and 50000),
  locale text not null check (length(locale) between 2 and 35 and locale ~ '^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$'),
  question text check (question is null or length(question) between 1 and 1000),
  reference_answer text check (reference_answer is null or length(reference_answer) between 1 and 1000),
  evaluation_criteria text check (evaluation_criteria is null or length(evaluation_criteria) between 1 and 1000),
  generation_confidence numeric(4, 3) not null check (generation_confidence between 0 and 1),
  reward_seconds integer not null check (reward_seconds between 1 and 3600),
  regeneration_count smallint not null default 0 check (regeneration_count between 0 and 1),
  answer_attempt_count smallint not null default 0 check (answer_attempt_count between 0 and 100),
  expires_at timestamptz not null,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, client_request_id),
  check (
    (status = 'active' and source_text is not null and question is not null and reference_answer is not null and evaluation_criteria is not null and completed_at is null)
    or
    (status <> 'active' and source_text is null and reference_answer is null and evaluation_criteria is null and completed_at is not null)
  )
);

create unique index study_sessions_one_active_user_idx
  on public.study_sessions (user_id) where status = 'active';
create index study_sessions_user_created_idx
  on public.study_sessions (user_id, created_at desc);
create index study_sessions_expiry_idx
  on public.study_sessions (expires_at) where status = 'active';

create table public.study_reward_transactions (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid not null references public.study_sessions(id) on delete restrict,
  amount_seconds integer not null check (amount_seconds > 0),
  earned_on date not null default ((now() at time zone 'utc')::date),
  transaction_type text not null default 'study_reward' check (transaction_type = 'study_reward'),
  created_at timestamptz not null default now(),
  unique (session_id)
);

create index study_reward_transactions_user_day_idx
  on public.study_reward_transactions (user_id, earned_on);

create table public.user_entitlements (
  user_id uuid not null references auth.users(id) on delete cascade,
  entitlement_id text not null check (length(entitlement_id) between 1 and 255),
  is_active boolean not null default false,
  product_id text,
  environment text check (environment is null or environment in ('SANDBOX', 'PRODUCTION')),
  expires_at timestamptz,
  source text not null default 'revenuecat' check (source = 'revenuecat'),
  last_synced_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, entitlement_id),
  check (not is_active or expires_at is null or expires_at > last_synced_at - interval '5 minutes')
);

create index user_entitlements_active_idx
  on public.user_entitlements (user_id, entitlement_id) where is_active;

create table public.revenuecat_webhook_events (
  event_id text primary key check (length(event_id) between 1 and 255),
  event_type text not null check (length(event_type) between 1 and 100),
  app_user_id text,
  environment text check (environment is null or environment in ('SANDBOX', 'PRODUCTION')),
  event_timestamp timestamptz,
  status text not null default 'processing' check (status in ('processing', 'processed', 'failed')),
  attempt_count integer not null default 1 check (attempt_count > 0),
  processing_started_at timestamptz not null default now(),
  processed_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index revenuecat_webhook_events_status_idx
  on public.revenuecat_webhook_events (status, processing_started_at);

create function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger study_configuration_updated_at
before update on public.study_configuration
for each row execute function private.set_updated_at();
create trigger study_sessions_updated_at
before update on public.study_sessions
for each row execute function private.set_updated_at();
create trigger user_entitlements_updated_at
before update on public.user_entitlements
for each row execute function private.set_updated_at();
create trigger revenuecat_webhook_events_updated_at
before update on public.revenuecat_webhook_events
for each row execute function private.set_updated_at();

alter table public.study_configuration enable row level security;
alter table public.study_sessions enable row level security;
alter table public.study_reward_transactions enable row level security;
alter table public.user_entitlements enable row level security;
alter table public.revenuecat_webhook_events enable row level security;

revoke all on table public.study_configuration from anon, authenticated;
revoke all on table public.study_sessions from anon, authenticated;
revoke all on table public.study_reward_transactions from anon, authenticated;
revoke all on table public.user_entitlements from anon, authenticated;
revoke all on table public.revenuecat_webhook_events from anon, authenticated;

grant select, insert, update, delete on table public.study_configuration to service_role;
grant select, insert, update, delete on table public.study_sessions to service_role;
grant select, insert, update, delete on table public.study_reward_transactions to service_role;
grant select, insert, update, delete on table public.user_entitlements to service_role;
grant select, insert, update, delete on table public.revenuecat_webhook_events to service_role;

create or replace function public.cleanup_expired_study_sessions()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  affected integer;
begin
  update public.study_sessions
  set status = 'expired',
      source_text = null,
      reference_answer = null,
      evaluation_criteria = null,
      completed_at = now()
  where status = 'active' and expires_at <= now();
  get diagnostics affected = row_count;
  return affected;
end;
$$;

create or replace function public.prepare_study_generation(
  p_user_id uuid,
  p_client_request_id uuid default null,
  p_session_id uuid default null,
  p_clear_other_active boolean default false
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  config_record public.study_configuration;
  session_reward_seconds integer;
  earned_seconds integer;
  utc_day date := (now() at time zone 'utc')::date;
begin
  if p_user_id is null then
    raise exception using errcode = '22004', message = 'user is required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':' || utc_day::text, 0));

  if p_client_request_id is not null and exists (
    select 1 from public.study_sessions
    where user_id = p_user_id and client_request_id = p_client_request_id
  ) then
    return false;
  end if;

  select * into config_record
  from public.study_configuration
  where id = true and enabled = true;
  if not found then
    raise exception using errcode = 'P0001', message = 'study rewards are disabled';
  end if;

  if config_record.entitlement_required and not exists (
    select 1 from public.user_entitlements
    where user_id = p_user_id
      and entitlement_id = config_record.entitlement_id
      and is_active
      and (expires_at is null or expires_at > now())
  ) then
    raise exception using errcode = '42501', message = 'active entitlement required';
  end if;

  if p_session_id is not null then
    select reward_seconds into session_reward_seconds
    from public.study_sessions
    where id = p_session_id and user_id = p_user_id and status = 'active' and expires_at > now()
    for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'active study session not found';
    end if;
  else
    session_reward_seconds := config_record.reward_seconds;
  end if;

  select coalesce(sum(amount_seconds), 0)::integer into earned_seconds
  from public.study_reward_transactions
  where user_id = p_user_id and earned_on = utc_day;
  if config_record.daily_cap_seconds - earned_seconds < session_reward_seconds then
    raise exception using errcode = 'P0001', message = 'daily study reward cap reached';
  end if;

  if p_clear_other_active then
    if p_client_request_id is null then
      raise exception using errcode = '22004', message = 'client request is required';
    end if;
    update public.study_sessions
    set status = 'abandoned',
        source_text = null,
        reference_answer = null,
        evaluation_criteria = null,
        completed_at = now()
    where user_id = p_user_id
      and status = 'active'
      and client_request_id <> p_client_request_id;
  end if;

  return true;
end;
$$;

create or replace function public.grant_study_reward(p_user_id uuid, p_session_id uuid, p_regeneration_count smallint)
returns public.study_reward_transactions
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_session public.study_sessions;
  existing_transaction public.study_reward_transactions;
  new_transaction public.study_reward_transactions;
  cap_seconds integer;
  earned_seconds integer;
  remaining_seconds integer;
  requires_entitlement boolean;
  required_entitlement_id text;
  utc_day date := (now() at time zone 'utc')::date;
begin
  if p_user_id is null or p_session_id is null then
    raise exception using errcode = '22004', message = 'user and session are required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':' || utc_day::text, 0));

  select * into existing_transaction
  from public.study_reward_transactions
  where session_id = p_session_id;
  if found then
    if existing_transaction.user_id <> p_user_id then
      raise exception using errcode = '42501', message = 'session ownership mismatch';
    end if;
    return existing_transaction;
  end if;

  select * into target_session
  from public.study_sessions
  where id = p_session_id and user_id = p_user_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'study session not found';
  end if;
  if target_session.status <> 'active' then
    raise exception using errcode = 'P0001', message = 'study session is not active';
  end if;
  if target_session.regeneration_count <> p_regeneration_count then
    raise exception using errcode = '40001', message = 'study session question changed';
  end if;
  if target_session.expires_at <= now() then
    update public.study_sessions
    set status = 'expired', source_text = null, reference_answer = null, evaluation_criteria = null, completed_at = now()
    where id = p_session_id;
    return null;
  end if;

  select daily_cap_seconds, entitlement_required, entitlement_id
  into cap_seconds, requires_entitlement, required_entitlement_id
  from public.study_configuration where id = true and enabled = true;
  if not found then
    raise exception using errcode = 'P0001', message = 'study rewards are disabled';
  end if;

  if requires_entitlement and not exists (
    select 1 from public.user_entitlements
    where user_id = p_user_id
      and entitlement_id = required_entitlement_id
      and is_active
      and (expires_at is null or expires_at > now())
  ) then
    raise exception using errcode = '42501', message = 'active entitlement required';
  end if;

  select coalesce(sum(amount_seconds), 0)::integer into earned_seconds
  from public.study_reward_transactions
  where user_id = p_user_id and earned_on = utc_day;
  remaining_seconds := cap_seconds - earned_seconds;
  if remaining_seconds < target_session.reward_seconds then
    raise exception using errcode = 'P0001', message = 'daily study reward cap reached';
  end if;

  insert into public.study_reward_transactions (user_id, session_id, amount_seconds, earned_on)
  values (p_user_id, p_session_id, target_session.reward_seconds, utc_day)
  returning * into new_transaction;

  update public.study_sessions
  set status = 'passed', source_text = null, reference_answer = null, evaluation_criteria = null, completed_at = now()
  where id = p_session_id;

  return new_transaction;
end;
$$;

create or replace function public.claim_revenuecat_webhook_event(
  p_event_id text,
  p_event_type text,
  p_app_user_id text,
  p_environment text,
  p_event_timestamp timestamptz
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  claimed boolean;
begin
  insert into public.revenuecat_webhook_events (
    event_id, event_type, app_user_id, environment, event_timestamp
  ) values (
    p_event_id, p_event_type, p_app_user_id, p_environment, p_event_timestamp
  )
  on conflict (event_id) do update
  set status = 'processing',
      attempt_count = public.revenuecat_webhook_events.attempt_count + 1,
      processing_started_at = now(),
      last_error = null
  where public.revenuecat_webhook_events.status = 'failed'
     or (
       public.revenuecat_webhook_events.status = 'processing'
       and public.revenuecat_webhook_events.processing_started_at < now() - interval '2 minutes'
     )
  returning true into claimed;
  return coalesce(claimed, false);
end;
$$;

create or replace function public.complete_revenuecat_webhook_event(
  p_event_id text,
  p_error text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.revenuecat_webhook_events
  set status = case when p_error is null then 'processed' else 'failed' end,
      processed_at = case when p_error is null then now() else null end,
      last_error = case when p_error is null then null else left(p_error, 500) end
  where event_id = p_event_id;
end;
$$;

revoke all on function public.cleanup_expired_study_sessions() from public, anon, authenticated;
revoke all on function public.prepare_study_generation(uuid, uuid, uuid, boolean) from public, anon, authenticated;
revoke all on function public.grant_study_reward(uuid, uuid, smallint) from public, anon, authenticated;
revoke all on function public.claim_revenuecat_webhook_event(text, text, text, text, timestamptz) from public, anon, authenticated;
revoke all on function public.complete_revenuecat_webhook_event(text, text) from public, anon, authenticated;
grant execute on function public.cleanup_expired_study_sessions() to service_role;
grant execute on function public.prepare_study_generation(uuid, uuid, uuid, boolean) to service_role;
grant execute on function public.grant_study_reward(uuid, uuid, smallint) to service_role;
grant execute on function public.claim_revenuecat_webhook_event(text, text, text, text, timestamptz) to service_role;
grant execute on function public.complete_revenuecat_webhook_event(text, text) to service_role;

revoke execute on function private.set_updated_at() from public, anon, authenticated;
