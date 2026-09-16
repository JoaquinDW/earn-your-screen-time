begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

select ok((select relrowsecurity from pg_class where oid = 'public.study_configuration'::regclass), 'configuration has RLS');
select ok((select relrowsecurity from pg_class where oid = 'public.study_sessions'::regclass), 'sessions have RLS');
select ok((select relrowsecurity from pg_class where oid = 'public.study_reward_transactions'::regclass), 'rewards have RLS');
select ok((select relrowsecurity from pg_class where oid = 'public.user_entitlements'::regclass), 'entitlements have RLS');
select ok((select relrowsecurity from pg_class where oid = 'public.revenuecat_webhook_events'::regclass), 'webhook events have RLS');

select ok(not has_table_privilege('anon', 'public.study_configuration', 'select,insert,update,delete'), 'anon cannot access configuration');
select ok(not has_table_privilege('authenticated', 'public.study_sessions', 'select,insert,update,delete'), 'authenticated cannot access sessions');
select ok(not has_table_privilege('authenticated', 'public.study_reward_transactions', 'select,insert,update,delete'), 'authenticated cannot access rewards');
select ok(not has_table_privilege('authenticated', 'public.user_entitlements', 'select,insert,update,delete'), 'authenticated cannot access entitlements');
select ok(not has_table_privilege('authenticated', 'public.revenuecat_webhook_events', 'select,insert,update,delete'), 'authenticated cannot access webhook events');
select ok(not has_function_privilege('authenticated', 'public.grant_study_reward(uuid,uuid,smallint)', 'execute'), 'authenticated cannot call reward grant');
select ok(not has_function_privilege('authenticated', 'public.prepare_study_generation(uuid,uuid,uuid,boolean)', 'execute'), 'authenticated cannot call generation preflight');
select is((select reward_seconds from public.study_configuration where id = true), 900, 'default reward is fifteen minutes');
select is((select max_regenerations from public.study_configuration where id = true), 1::smallint, 'default allows one alternative question');

select * from finish();
rollback;
