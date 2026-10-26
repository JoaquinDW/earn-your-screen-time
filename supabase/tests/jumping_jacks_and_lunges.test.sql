begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('66666666-6666-4666-8666-666666666661', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'jacks-1@example.com', '', now(), now());

update public.exercise_configuration
set enabled = true,
    jumping_jack_enabled = true,
    lunge_enabled = true,
    entitlement_required = false,
    minimum_app_version = '1.0.0',
    detection_version = 'pose-v1',
    jumping_jack_minimum_rep_duration_seconds = 0.4,
    lunge_minimum_rep_duration_seconds = 0.6
where id = true;

select results_eq(
  $$select target_reps::integer, reward_seconds from public.exercise_challenges where exercise_type = 'jumping_jack' order by display_order$$,
  $$values (20, 300), (40, 600), (80, 1200)$$,
  'jumping jacks ask for four times the push-up repetitions for the same minutes'
);
select results_eq(
  $$select target_reps::integer, reward_seconds from public.exercise_challenges where exercise_type = 'lunge' order by display_order$$,
  $$values (10, 300), (20, 600), (40, 1200)$$,
  'lunges count each leg, so they ask for twice the push-up repetitions'
);

-- Jumping jacks
select is(
  (public.start_exercise_session('66666666-6666-4666-8666-666666666661', '71000000-0000-4000-8000-000000000001', 20, '1.4.0', 'pose-v1', 'jumping_jack')).exercise_type,
  'jumping_jack',
  'a jumping jack session records its exercise'
);
update public.exercise_sessions set created_at = now() - interval '30 seconds'
where client_request_id = '71000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select public.claim_exercise_reward('66666666-6666-4666-8666-666666666661', (select id from public.exercise_sessions where client_request_id = '71000000-0000-4000-8000-000000000001'), 20, 5, now(), 'pose-v1')$$,
  '22023',
  'invalid exercise duration',
  'jumping jacks are held to their own minimum repetition time'
);
select is(
  (public.claim_exercise_reward('66666666-6666-4666-8666-666666666661', (select id from public.exercise_sessions where client_request_id = '71000000-0000-4000-8000-000000000001'), 20, 10, now(), 'pose-v1')).source_type,
  'jumping_jacks',
  'a jumping jack reward is filed under its own source'
);

-- Lunges
select is(
  (public.start_exercise_session('66666666-6666-4666-8666-666666666661', '71000000-0000-4000-8000-000000000002', 10, '1.4.0', 'pose-v1', 'lunge')).exercise_type,
  'lunge',
  'a lunge session records its exercise'
);
update public.exercise_sessions set created_at = now() - interval '30 seconds'
where client_request_id = '71000000-0000-4000-8000-000000000002';
select is(
  (public.claim_exercise_reward('66666666-6666-4666-8666-666666666661', (select id from public.exercise_sessions where client_request_id = '71000000-0000-4000-8000-000000000002'), 10, 8, now(), 'pose-v1')).source_type,
  'lunges',
  'a lunge reward is filed under its own source'
);

-- The daily cap is shared: 600 earned plus 1200 of push-ups leaves 0 of the default 1800.
insert into public.reward_transactions (user_id, source_type, source_id, amount_seconds)
values ('66666666-6666-4666-8666-666666666661', 'pushups', '81000000-0000-4000-8000-000000000001', 1200);
update public.exercise_configuration set daily_cap_seconds = 1800 where id = true;
select throws_ok(
  $$select public.start_exercise_session('66666666-6666-4666-8666-666666666661', '71000000-0000-4000-8000-000000000003', 20, '1.4.0', 'pose-v1', 'jumping_jack')$$,
  'P0001',
  'daily pushups reward cap reached',
  'jumping jack, lunge and push-up minutes share the daily cap'
);
update public.exercise_configuration set daily_cap_seconds = 7200 where id = true;

-- Each new exercise can be switched off on its own.
update public.exercise_configuration set lunge_enabled = false where id = true;
select throws_ok(
  $$select public.start_exercise_session('66666666-6666-4666-8666-666666666661', '71000000-0000-4000-8000-000000000004', 10, '1.4.0', 'pose-v1', 'lunge')$$,
  'P0001',
  'exercise rewards are disabled',
  'disabling lunges stops new lunge sessions'
);
select lives_ok(
  $$select public.start_exercise_session('66666666-6666-4666-8666-666666666661', '71000000-0000-4000-8000-000000000005', 20, '1.4.0', 'pose-v1', 'jumping_jack')$$,
  'jumping jacks keep working while lunges are off'
);

select * from finish();
rollback;
