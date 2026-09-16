begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

select ok((select relrowsecurity from pg_class where oid = 'public.exercise_configuration'::regclass), 'exercise configuration has RLS');
select ok((select relrowsecurity from pg_class where oid = 'public.exercise_challenges'::regclass), 'exercise challenges have RLS');
select ok((select relrowsecurity from pg_class where oid = 'public.exercise_sessions'::regclass), 'exercise sessions have RLS');
select ok((select relrowsecurity from pg_class where oid = 'public.reward_transactions'::regclass), 'generic rewards have RLS');

select ok(not has_table_privilege('anon', 'public.exercise_configuration', 'select,insert,update,delete'), 'anon cannot access exercise configuration');
select ok(not has_table_privilege('authenticated', 'public.exercise_challenges', 'select,insert,update,delete'), 'authenticated cannot access challenges directly');
select ok(not has_table_privilege('authenticated', 'public.exercise_sessions', 'select,insert,update,delete'), 'authenticated cannot read or write sessions directly');
select ok(not has_table_privilege('authenticated', 'public.reward_transactions', 'select,insert,update,delete'), 'authenticated cannot read or write rewards directly');

select ok(not has_function_privilege('authenticated', 'public.cleanup_expired_exercise_sessions()', 'execute'), 'authenticated cannot run cleanup');
select ok(not has_function_privilege('authenticated', 'public.start_exercise_session(uuid,uuid,integer,text,text)', 'execute'), 'authenticated cannot call privileged start RPC');
select ok(not has_function_privilege('authenticated', 'public.claim_exercise_reward(uuid,uuid,integer,numeric,timestamptz,text)', 'execute'), 'authenticated cannot call privileged claim RPC');
select ok(has_function_privilege('service_role', 'public.start_exercise_session(uuid,uuid,integer,text,text)', 'execute'), 'service role can call start RPC');
select ok(has_function_privilege('service_role', 'public.claim_exercise_reward(uuid,uuid,integer,numeric,timestamptz,text)', 'execute'), 'service role can call claim RPC');

select is((select enabled from public.exercise_configuration where id = true), true, 'remote feature flag starts enabled');
select is((select daily_cap_seconds from public.exercise_configuration where id = true), 1800, 'daily cap is thirty minutes');
select results_eq(
  $$select target_reps::integer, reward_seconds from public.exercise_challenges order by display_order$$,
  $$values (5, 300), (10, 600), (20, 1200)$$,
  'challenges grant matching five, ten, and twenty minute rewards'
);
select is(
  (select count(*)::integer from information_schema.columns where table_schema = 'public' and table_name in ('exercise_sessions', 'reward_transactions') and column_name in ('frame', 'frames', 'landmark', 'landmarks')),
  0,
  'exercise persistence has no frame or landmark columns'
);

select * from finish();
rollback;
