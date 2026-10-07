begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('44444444-4444-4444-8444-444444444441', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'free-pushups-1@example.com', '', now(), now()),
  ('44444444-4444-4444-8444-444444444442', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'free-pushups-2@example.com', '', now(), now()),
  ('44444444-4444-4444-8444-444444444443', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pro-pushups@example.com', '', now(), now());

update public.exercise_configuration
set enabled = true,
    entitlement_required = true,
    free_rewards_per_user = 1,
    minimum_app_version = '1.0.0',
    detection_version = 'pose-v1'
where id = true;

-- A user with no entitlement and no earlier push-up reward gets exactly one.
select is(
  (public.start_exercise_session('44444444-4444-4444-8444-444444444441', '50000000-0000-4000-8000-000000000001', 5, '1.3.0', 'pose-v1')).target_reps,
  5::smallint,
  'a user who has not paid can start their first push-up challenge'
);
update public.exercise_sessions set created_at = now() - interval '10 seconds'
where client_request_id = '50000000-0000-4000-8000-000000000001';
select is(
  (public.claim_exercise_reward('44444444-4444-4444-8444-444444444441', (select id from public.exercise_sessions where client_request_id = '50000000-0000-4000-8000-000000000001'), 5, 2, now(), 'pose-v1')).amount_seconds,
  300,
  'the free reward is granted'
);
select is(
  (public.claim_exercise_reward('44444444-4444-4444-8444-444444444441', (select id from public.exercise_sessions where client_request_id = '50000000-0000-4000-8000-000000000001'), 5, 2, now(), 'pose-v1')).amount_seconds,
  300,
  'retrying the free claim returns its receipt rather than hitting the entitlement check'
);
select throws_ok(
  $$select public.start_exercise_session('44444444-4444-4444-8444-444444444441', '50000000-0000-4000-8000-000000000002', 5, '1.3.0', 'pose-v1')$$,
  '42501',
  'active entitlement required',
  'a second challenge requires Pro once the free reward is used'
);

-- A session started while the free reward was available cannot be claimed after it is used.
select is(
  (public.start_exercise_session('44444444-4444-4444-8444-444444444442', '50000000-0000-4000-8000-000000000003', 5, '1.3.0', 'pose-v1')).target_reps,
  5::smallint,
  'another free user can start their first challenge'
);
insert into public.reward_transactions (user_id, source_type, source_id, amount_seconds)
values ('44444444-4444-4444-8444-444444444442', 'pushups', '60000000-0000-4000-8000-000000000001', 300);
update public.exercise_sessions set created_at = now() - interval '10 seconds'
where client_request_id = '50000000-0000-4000-8000-000000000003';
select throws_ok(
  $$select public.claim_exercise_reward('44444444-4444-4444-8444-444444444442', (select id from public.exercise_sessions where client_request_id = '50000000-0000-4000-8000-000000000003'), 5, 2, now(), 'pose-v1')$$,
  '42501',
  'active entitlement required',
  'claim re-checks the free allowance, so two open sessions cannot both be free'
);

-- Pro is unaffected by the allowance.
insert into public.user_entitlements (user_id, entitlement_id, is_active, expires_at)
values ('44444444-4444-4444-8444-444444444443', 'Earn your Screen Time Pro', true, now() + interval '30 days');
insert into public.reward_transactions (user_id, source_type, source_id, amount_seconds)
values ('44444444-4444-4444-8444-444444444443', 'pushups', '60000000-0000-4000-8000-000000000002', 300);
select is(
  (public.start_exercise_session('44444444-4444-4444-8444-444444444443', '50000000-0000-4000-8000-000000000004', 5, '1.3.0', 'pose-v1')).target_reps,
  5::smallint,
  'a Pro user keeps starting challenges after earlier rewards'
);
update public.exercise_sessions set created_at = now() - interval '10 seconds'
where client_request_id = '50000000-0000-4000-8000-000000000004';
select is(
  (public.claim_exercise_reward('44444444-4444-4444-8444-444444444443', (select id from public.exercise_sessions where client_request_id = '50000000-0000-4000-8000-000000000004'), 5, 2, now(), 'pose-v1')).amount_seconds,
  300,
  'a Pro user keeps claiming'
);

-- The allowance is configuration: zero restores the Pro-only behaviour.
update public.exercise_configuration set free_rewards_per_user = 0 where id = true;
delete from public.reward_transactions where user_id = '44444444-4444-4444-8444-444444444442';
update public.exercise_sessions set status = 'cancelled'
where user_id = '44444444-4444-4444-8444-444444444442' and status = 'active';
select throws_ok(
  $$select public.start_exercise_session('44444444-4444-4444-8444-444444444442', '50000000-0000-4000-8000-000000000005', 5, '1.3.0', 'pose-v1')$$,
  '42501',
  'active entitlement required',
  'with no free rewards configured a user who has not paid is refused'
);

update public.exercise_configuration set free_rewards_per_user = 2 where id = true;
select ok(
  private.exercise_reward_allowed('44444444-4444-4444-8444-444444444441', (select c from public.exercise_configuration c where id = true)),
  'a larger allowance lets a user who used one free reward earn another'
);
select throws_ok(
  $$update public.exercise_configuration set free_rewards_per_user = 11 where id = true$$,
  '23514',
  null,
  'the allowance is bounded'
);

select * from finish();
rollback;
