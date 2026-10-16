-- Chi Hung / PeopleOps: rerunnable installation for this application's compatible schema.
-- Preserves business rows. Reinstalls application policies/functions/triggers.
-- Unrelated or structurally different tables need a reviewed migration.
begin;
set local search_path = public, extensions;
select pg_advisory_xact_lock(2414, 1001);
do $setup$
declare col text;
begin
 if to_regclass('public.attendance') is not null then
  foreach col in array array['id','employee_id','work_date','check_in','check_out','late_minutes','early_minutes','overtime_minutes'] loop
   if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='attendance' and column_name=col) then
    raise exception 'Existing public.attendance is incompatible: missing column %. No data has been deleted. Export the table definition before migrating.', col;
   end if;
  end loop;
 end if;
end $setup$;
create extension if not exists pgcrypto;
do $setup$ begin
 if not exists(select 1 from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname='public' and t.typname='app_role') then
 create type public.app_role as enum ('super_admin','hr_admin','department_manager','employee');
 end if;
end $setup$;
do $setup$ begin
 if not exists(select 1 from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname='public' and t.typname='employment_status') then
 create type public.employment_status as enum ('probation','active','on_leave','terminated');
 end if;
end $setup$;

create table if not exists departments(id uuid primary key default gen_random_uuid(), code text unique not null, name text not null, manager_id uuid, created_at timestamptz not null default now());
create table if not exists positions(id uuid primary key default gen_random_uuid(), department_id uuid references departments(id) on delete restrict, name text not null, level smallint not null default 1 check(level between 1 and 20));
create table if not exists employees(id uuid primary key default gen_random_uuid(), employee_code text unique not null, full_name text not null, work_email text unique not null, personal_email text, phone text, gender text, date_of_birth date, address text, department_id uuid references departments(id) on delete restrict, position_id uuid references positions(id) on delete restrict, manager_id uuid references employees(id) on delete set null, start_date date not null, status employment_status not null default 'probation', created_at timestamptz not null default now(), updated_at timestamptz not null default now());
do $setup$ begin
 if not exists(select 1 from pg_constraint where conrelid='public.departments'::regclass and conname='departments_manager_fk') then
 alter table public.departments add constraint departments_manager_fk foreign key(manager_id) references employees(id) on delete set null;
 end if;
end $setup$;
create table if not exists profiles(user_id uuid primary key references auth.users(id) on delete cascade, employee_id uuid unique references employees(id) on delete set null, role app_role not null default 'employee', active boolean not null default true);
create table if not exists contracts(id uuid primary key default gen_random_uuid(), employee_id uuid not null references employees(id) on delete restrict, contract_no text unique not null, type text not null, start_date date not null, end_date date, base_salary numeric(15,2) not null check(base_salary>=0), private_file_path text, created_at timestamptz not null default now(), check(end_date is null or end_date>=start_date));
create table if not exists attendance(id uuid primary key default gen_random_uuid(), employee_id uuid not null references employees(id) on delete cascade, work_date date not null, check_in timestamptz, check_out timestamptz, late_minutes int not null default 0 check(late_minutes>=0), early_minutes int not null default 0 check(early_minutes>=0), overtime_minutes int not null default 0 check(overtime_minutes>=0), unique(employee_id,work_date));
create table if not exists leave_requests(id uuid primary key default gen_random_uuid(), employee_id uuid not null references employees(id) on delete cascade, type text not null, start_date date not null, end_date date not null, days numeric(5,2) not null check(days>0), reason text, status text not null default 'pending' check(status in ('pending','approved','rejected','cancelled')), approver_id uuid references employees(id), created_at timestamptz not null default now(), check(end_date>=start_date));
create table if not exists payrolls(id uuid primary key default gen_random_uuid(), employee_id uuid not null references employees(id) on delete restrict, period date not null, base_salary numeric(15,2) not null, allowance numeric(15,2) not null default 0, bonus numeric(15,2) not null default 0, deduction numeric(15,2) not null default 0, insurance numeric(15,2) not null default 0, tax numeric(15,2) not null default 0, status text not null default 'draft' check(status in ('draft','approved','paid')), unique(employee_id,period));
create table if not exists audit_logs(id bigint generated always as identity primary key, actor_id uuid references auth.users(id), action text not null, entity_type text not null, entity_id text, metadata jsonb not null default '{}', ip inet, created_at timestamptz not null default now());

create or replace function public.current_role() returns app_role language sql stable security definer set search_path=public as $$ select role from profiles where user_id=auth.uid() and active=true $$;
create or replace function public.current_employee_id() returns uuid language sql stable security definer set search_path=public as $$ select employee_id from profiles where user_id=auth.uid() and active=true $$;

alter table employees enable row level security; alter table contracts enable row level security; alter table attendance enable row level security; alter table leave_requests enable row level security; alter table payrolls enable row level security; alter table profiles enable row level security; alter table audit_logs enable row level security;
create index if not exists employee_department_idx on employees(department_id); create index if not exists attendance_date_idx on attendance(work_date,employee_id); create index if not exists leave_status_idx on leave_requests(status,created_at); create index if not exists contract_expiry_idx on contracts(end_date) where end_date is not null;


-- PeopleOps / Chi Hung: extend 001_init.sql. Run once, as postgres.
-- All statements are transactional; no existing business rows are deleted.
create schema if not exists app_private;
revoke all on schema app_private from public;
grant usage on schema app_private to authenticated;

create or replace function app_private.is_hr() returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.profiles where user_id=auth.uid() and active and role in ('super_admin','hr_admin'))
$$;
create or replace function app_private.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.profiles where user_id=auth.uid() and active and role='super_admin')
$$;
create or replace function app_private.is_active() returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.profiles where user_id=auth.uid() and active)
$$;
create or replace function app_private.can_read_employee(p_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.profiles p where p.user_id=auth.uid() and p.active and
 (p.role in ('super_admin','hr_admin') or p.employee_id=p_id or
 (p.role='department_manager' and exists(select 1 from public.employees e where e.id=p_id and e.manager_id=p.employee_id))))
$$;
create or replace function public.current_role() returns public.app_role
language sql stable security definer set search_path = '' as $$
 select role from public.profiles where user_id=auth.uid() and active
$$;
create or replace function public.current_employee_id() returns uuid
language sql stable security definer set search_path = '' as $$
 select employee_id from public.profiles where user_id=auth.uid() and active
$$;

alter table public.departments add column if not exists parent_id uuid references public.departments(id) on delete restrict;
do $setup$ begin
 if not exists(select 1 from pg_constraint where conrelid='public.departments'::regclass and conname='department_not_own_parent') then
 alter table public.departments add constraint department_not_own_parent check(parent_id is distinct from id);
 end if;
end $setup$;
do $setup$ begin
 if not exists(select 1 from pg_constraint where conrelid='public.employees'::regclass and conname='employee_not_own_manager') then
 alter table public.employees add constraint employee_not_own_manager check(manager_id is distinct from id);
 end if;
end $setup$;
do $setup$ begin
 if not exists(select 1 from pg_constraint where conrelid='public.attendance'::regclass and conname='attendance_time_order') then
 alter table public.attendance add constraint attendance_time_order check(check_out is null or (check_in is not null and check_out>=check_in));
 end if;
end $setup$;
alter table public.payrolls add column if not exists net_salary numeric(15,2) generated always as (base_salary+allowance+bonus-deduction-insurance-tax) stored;
do $setup$ begin
 if not exists(select 1 from pg_constraint where conrelid='public.payrolls'::regclass and conname='payroll_nonnegative') then
 alter table public.payrolls add constraint payroll_nonnegative check(least(base_salary,allowance,bonus,deduction,insurance,tax)>=0);
 end if;
end $setup$;
do $setup$ begin
 if not exists(select 1 from pg_constraint where conrelid='public.payrolls'::regclass and conname='payroll_month_start') then
 alter table public.payrolls add constraint payroll_month_start check(extract(day from period)=1);
 end if;
end $setup$;

create table if not exists public.company_settings (
 id boolean primary key default true check(id), company_name text not null,
 timezone text not null default 'Asia/Ho_Chi_Minh' check(timezone='Asia/Ho_Chi_Minh'),
 currency text not null default 'VND' check(currency='VND'),
 address text, updated_at timestamptz not null default now()
);
create table if not exists public.work_shifts (
 id uuid primary key default gen_random_uuid(), code text unique not null, name text not null,
 start_time time not null, end_time time not null, break_minutes integer not null default 60 check(break_minutes>=0),
 active boolean not null default true
);
create table if not exists public.shift_assignments (
 id uuid primary key default gen_random_uuid(), employee_id uuid not null references public.employees(id) on delete restrict,
 shift_id uuid not null references public.work_shifts(id) on delete restrict, work_date date not null,
 unique(employee_id,work_date)
);
create table if not exists public.holidays (
 id uuid primary key default gen_random_uuid(), holiday_date date unique not null, name text not null
);
create table if not exists public.attendance_adjustments (
 id uuid primary key default gen_random_uuid(), employee_id uuid not null references public.employees(id) on delete restrict,
 work_date date not null, requested_check_in timestamptz, requested_check_out timestamptz,
 reason text not null check(length(trim(reason))>0), status text not null default 'pending' check(status in ('pending','approved','rejected')),
 reviewed_by uuid references public.employees(id), reviewed_at timestamptz, created_at timestamptz not null default now(),
 check(requested_check_out is null or (requested_check_in is not null and requested_check_out>=requested_check_in))
);
create table if not exists public.leave_types (
 code text primary key, name text not null, paid boolean not null default true, deduct_balance boolean not null default true
);
create table if not exists public.leave_balances (
 employee_id uuid not null references public.employees(id) on delete restrict,
 leave_type text not null references public.leave_types(code), year integer not null check(year between 2000 and 2200),
 entitled_days numeric(6,2) not null default 0 check(entitled_days>=0),
 used_days numeric(6,2) not null default 0 check(used_days>=0),
 remaining_days numeric(6,2) generated always as (entitled_days-used_days) stored,
 primary key(employee_id,leave_type,year), check(used_days<=entitled_days)
);
-- Legacy leave types must be reconciled before applying this FK on a populated project.
do $setup$ begin
 if not exists(select 1 from pg_constraint where conrelid='public.leave_requests'::regclass and conname='leave_type_fk') then
 alter table public.leave_requests add constraint leave_type_fk foreign key(type) references public.leave_types(code) not valid;
 end if;
end $setup$;
alter table public.leave_requests add column if not exists reviewed_at timestamptz;
alter table public.leave_requests add column if not exists decision_note text;
create table if not exists public.contract_amendments (
 id uuid primary key default gen_random_uuid(), contract_id uuid not null references public.contracts(id) on delete restrict,
 amendment_no text unique not null, effective_date date not null, description text not null,
 private_file_path text, created_at timestamptz not null default now()
);
create table if not exists public.employee_documents (
 id uuid primary key default gen_random_uuid(), employee_id uuid not null references public.employees(id) on delete restrict,
 title text not null, document_type text not null, storage_path text unique not null,
 created_at timestamptz not null default now()
);
create table if not exists public.performance_cycles (
 id uuid primary key default gen_random_uuid(), name text not null, start_date date not null, end_date date not null,
 status text not null default 'draft' check(status in ('draft','active','closed')), check(end_date>=start_date)
);
create table if not exists public.objectives (
 id uuid primary key default gen_random_uuid(), cycle_id uuid not null references public.performance_cycles(id) on delete restrict,
 employee_id uuid not null references public.employees(id) on delete restrict, title text not null,
 description text, created_at timestamptz not null default now()
);
create table if not exists public.key_results (
 id uuid primary key default gen_random_uuid(), objective_id uuid not null references public.objectives(id) on delete cascade,
 title text not null, target_value numeric not null check(target_value>0), current_value numeric not null default 0 check(current_value>=0),
 unit text not null default '%', updated_at timestamptz not null default now()
);
create table if not exists public.performance_reviews (
 id uuid primary key default gen_random_uuid(), cycle_id uuid not null references public.performance_cycles(id) on delete restrict,
 employee_id uuid not null references public.employees(id) on delete restrict,
 reviewer_id uuid not null references public.employees(id) on delete restrict,
 score numeric(4,2) check(score between 0 and 5), feedback text,
 status text not null default 'draft' check(status in ('draft','published')),
 created_at timestamptz not null default now(), unique(cycle_id,employee_id,reviewer_id)
);
create table if not exists public.job_openings (
 id uuid primary key default gen_random_uuid(), title text not null,
 department_id uuid references public.departments(id) on delete restrict, description text,
 headcount integer not null default 1 check(headcount>0),
 status text not null default 'draft' check(status in ('draft','open','closed')),
 opened_on date, closed_on date, created_at timestamptz not null default now(),
 check(closed_on is null or opened_on is null or closed_on>=opened_on)
);
create table if not exists public.candidates (
 id uuid primary key default gen_random_uuid(), full_name text not null, email text not null,
 phone text, resume_path text, notes text, created_at timestamptz not null default now()
);
create table if not exists public.job_applications (
 id uuid primary key default gen_random_uuid(), job_id uuid not null references public.job_openings(id) on delete restrict,
 candidate_id uuid not null references public.candidates(id) on delete restrict,
 stage text not null default 'applied' check(stage in ('applied','screening','interview','offer','hired','rejected','withdrawn')),
 created_at timestamptz not null default now(), unique(job_id,candidate_id)
);
create table if not exists public.interviews (
 id uuid primary key default gen_random_uuid(), application_id uuid not null references public.job_applications(id) on delete cascade,
 interviewer_id uuid not null references public.employees(id) on delete restrict,
 starts_at timestamptz not null, ends_at timestamptz not null, location text, feedback text,
 status text not null default 'scheduled' check(status in ('scheduled','completed','cancelled')), check(ends_at>starts_at)
);
create table if not exists public.assets (
 id uuid primary key default gen_random_uuid(), asset_code text unique not null, name text not null,
 category text not null, serial_number text unique, purchased_on date,
 purchase_price numeric(15,2) check(purchase_price>=0),
 status text not null default 'available' check(status in ('available','assigned','maintenance','retired')),
 created_at timestamptz not null default now()
);
create table if not exists public.asset_assignments (
 id uuid primary key default gen_random_uuid(), asset_id uuid not null references public.assets(id) on delete restrict,
 employee_id uuid not null references public.employees(id) on delete restrict,
 assigned_at timestamptz not null default now(), returned_at timestamptz,
 handover_notes text, return_notes text, check(returned_at is null or returned_at>=assigned_at)
);
create unique index if not exists one_active_asset_assignment on public.asset_assignments(asset_id) where returned_at is null;
create table if not exists public.report_exports (
 id uuid primary key default gen_random_uuid(), requested_by uuid not null references auth.users(id) on delete restrict,
 report_type text not null, filters jsonb not null default '{}',
 status text not null default 'pending' check(status in ('pending','processing','completed','failed')),
 storage_path text, error_message text, created_at timestamptz not null default now(), completed_at timestamptz
);
create table if not exists public.ai_reports (
 id uuid primary key default gen_random_uuid(), requested_by uuid not null references auth.users(id) on delete restrict,
 title text not null, content text not null, period_start date, period_end date,
 created_at timestamptz not null default now(), check(period_end is null or period_start is null or period_end>=period_start)
);
create table if not exists public.notifications (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 title text not null, body text, read_at timestamptz, created_at timestamptz not null default now()
);

-- Replace original policies with a consistent access model. Only known application tables are affected.
do $$ declare t text; p record; begin
 foreach t in array array['departments','positions','employees','profiles','contracts','attendance','leave_requests','payrolls','audit_logs',
 'company_settings','work_shifts','shift_assignments','holidays','attendance_adjustments','leave_types','leave_balances',
 'contract_amendments','employee_documents','performance_cycles','objectives','key_results','performance_reviews',
 'job_openings','candidates','job_applications','interviews','assets','asset_assignments','report_exports','ai_reports','notifications'] loop
  execute format('alter table public.%I enable row level security',t);
  for p in select policyname from pg_policies where schemaname='public' and tablename=t loop
   execute format('drop policy %I on public.%I',p.policyname,t);
  end loop;
  execute format('revoke all on public.%I from anon, authenticated',t);
  execute format('grant select, insert, update, delete on public.%I to authenticated',t);
  execute format('grant all on public.%I to service_role',t);
 end loop;
end $$;

-- HR owns business mutations. Staff mutations use narrow RPCs below.
do $$ declare t text; begin
 foreach t in array array['departments','positions','employees','contracts','attendance','leave_requests','payrolls',
 'work_shifts','shift_assignments','holidays','attendance_adjustments','leave_types','leave_balances','contract_amendments',
 'employee_documents','performance_cycles','objectives','key_results','performance_reviews','job_openings','candidates',
 'job_applications','interviews','assets','asset_assignments','report_exports','ai_reports','notifications'] loop
  execute format('create policy hr_manage on public.%I for all to authenticated using (app_private.is_hr()) with check (app_private.is_hr())',t);
 end loop;
 foreach t in array array['departments','positions','company_settings','work_shifts','holidays','leave_types','performance_cycles'] loop
  execute format('create policy staff_read on public.%I for select to authenticated using (app_private.is_active())',t);
 end loop;
 foreach t in array array['attendance','leave_requests','shift_assignments','attendance_adjustments','leave_balances','objectives','asset_assignments'] loop
  execute format('create policy scoped_read on public.%I for select to authenticated using (app_private.can_read_employee(employee_id))',t);
 end loop;
end $$;
drop policy if exists employee_scope on public.employees;
create policy employee_scope on public.employees for select to authenticated using(app_private.can_read_employee(id));
drop policy if exists contract_self on public.contracts;
create policy contract_self on public.contracts for select to authenticated using(employee_id=public.current_employee_id());
drop policy if exists payroll_self on public.payrolls;
create policy payroll_self on public.payrolls for select to authenticated using(employee_id=public.current_employee_id() and status in ('approved','paid'));
drop policy if exists document_self on public.employee_documents;
create policy document_self on public.employee_documents for select to authenticated using(employee_id=public.current_employee_id());
drop policy if exists amendment_self on public.contract_amendments;
create policy amendment_self on public.contract_amendments for select to authenticated using(exists(select 1 from public.contracts c where c.id=contract_id));
drop policy if exists kr_scope on public.key_results;
create policy kr_scope on public.key_results for select to authenticated using(exists(select 1 from public.objectives o where o.id=objective_id));
drop policy if exists review_self on public.performance_reviews;
create policy review_self on public.performance_reviews for select to authenticated using(employee_id=public.current_employee_id() and status='published');
drop policy if exists asset_self on public.assets;
create policy asset_self on public.assets for select to authenticated using(exists(select 1 from public.asset_assignments a where a.asset_id=assets.id and a.employee_id=public.current_employee_id() and a.returned_at is null));
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated using(user_id=auth.uid() or app_private.is_admin());
drop policy if exists profiles_admin on public.profiles;
create policy profiles_admin on public.profiles for all to authenticated using(app_private.is_admin()) with check(app_private.is_admin());
drop policy if exists settings_admin on public.company_settings;
create policy settings_admin on public.company_settings for all to authenticated using(app_private.is_admin()) with check(app_private.is_admin());
drop policy if exists audit_read on public.audit_logs;
create policy audit_read on public.audit_logs for select to authenticated using(app_private.is_admin());
drop policy if exists notification_self on public.notifications;
create policy notification_self on public.notifications for select to authenticated using(user_id=auth.uid() and app_private.is_active());

-- No audit payloads with salaries, candidate details or documents are copied into metadata.
create or replace function app_private.audit_change() returns trigger
language plpgsql security definer set search_path='' as $$
declare row_data jsonb; begin
 if TG_OP='DELETE' then row_data=to_jsonb(old); else row_data=to_jsonb(new); end if;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata)
 values(auth.uid(),TG_OP,TG_TABLE_NAME,coalesce(row_data->>'id',row_data->>'user_id',row_data->>'employee_id'),jsonb_build_object('source','database'));
 if TG_OP='DELETE' then return old; end if; return new;
end $$;
create or replace function app_private.touch_updated_at() returns trigger
language plpgsql set search_path='' as $$ begin new.updated_at=now(); return new; end $$;
create or replace trigger employees_updated before update on public.employees for each row execute function app_private.touch_updated_at();
create or replace trigger settings_updated before update on public.company_settings for each row execute function app_private.touch_updated_at();
create or replace trigger key_results_updated before update on public.key_results for each row execute function app_private.touch_updated_at();
do $$ declare t text; begin
 foreach t in array array['employees','profiles','departments','contracts','contract_amendments','payrolls','attendance','attendance_adjustments',
 'leave_requests','leave_balances','employee_documents','performance_reviews','candidates','assets','asset_assignments','company_settings','report_exports','ai_reports'] loop
 execute format('create or replace trigger audit_change after insert or update or delete on public.%I for each row execute function app_private.audit_change()',t);
 end loop;
end $$;

-- Auth users never select their own application role from signup metadata.
create or replace function app_private.handle_new_user() returns trigger
language plpgsql security definer set search_path='' as $$ begin
 insert into public.profiles(user_id,role,active) values(new.id,'employee',true) on conflict(user_id) do nothing;
 return new;
end $$;
create or replace trigger peopleops_auth_user_created after insert on auth.users for each row execute function app_private.handle_new_user();
insert into public.profiles(user_id) select id from auth.users on conflict(user_id) do nothing;

create or replace function public.check_in() returns public.attendance
language plpgsql security definer set search_path='' as $$
declare eid uuid:=public.current_employee_id(); r public.attendance; begin
 if eid is null then raise exception 'An active linked employee is required'; end if;
 insert into public.attendance(employee_id,work_date,check_in)
 values(eid,(now() at time zone 'Asia/Ho_Chi_Minh')::date,now())
 on conflict(employee_id,work_date) do nothing returning * into r;
 if r.id is null then raise exception 'Already checked in for this date'; end if;
 return r;
end $$;
create or replace function public.check_out() returns public.attendance
language plpgsql security definer set search_path='' as $$
declare eid uuid:=public.current_employee_id(); r public.attendance; begin
 if eid is null then raise exception 'An active linked employee is required'; end if;
 update public.attendance set check_out=now() where employee_id=eid
 and work_date=(now() at time zone 'Asia/Ho_Chi_Minh')::date and check_in is not null and check_out is null returning * into r;
 if r.id is null then raise exception 'No open attendance record for today'; end if;
 return r;
end $$;
-- Full-day leave only: weekends and holidays excluded. Cross-year requests must be split.
create or replace function public.request_leave(p_type text,p_start date,p_end date,p_reason text) returns public.leave_requests
language plpgsql security definer set search_path='' as $$
declare eid uuid:=public.current_employee_id(); n integer; r public.leave_requests; begin
 if eid is null then raise exception 'An active linked employee is required'; end if;
 if p_start is null or p_end is null or p_end<p_start or p_end-p_start>366 or extract(year from p_start)<>extract(year from p_end) then
 raise exception 'Invalid date range; split requests by calendar year'; end if;
 if not exists(select 1 from public.leave_types where code=p_type) then raise exception 'Invalid leave type'; end if;
 perform 1 from public.employees where id=eid for update;
 if exists(select 1 from public.leave_requests where employee_id=eid and status in ('pending','approved') and start_date<=p_end and end_date>=p_start) then
 raise exception 'Overlapping leave request'; end if;
 select count(*) into n from generate_series(0,p_end-p_start) g(i)
 where extract(isodow from (p_start+g.i)) between 1 and 5
 and not exists(select 1 from public.holidays h where h.holiday_date=p_start+g.i);
 if n=0 then raise exception 'No working days in requested range'; end if;
 insert into public.leave_requests(employee_id,type,start_date,end_date,days,reason)
 values(eid,p_type,p_start,p_end,n,p_reason) returning * into r; return r;
end $$;
create or replace function public.decide_leave(p_id uuid,p_approve boolean,p_note text default null) returns public.leave_requests
language plpgsql security definer set search_path='' as $$
declare r public.leave_requests; eid uuid:=public.current_employee_id(); deduct boolean; begin
 if p_approve is null then raise exception 'Decision is required'; end if;
 select * into r from public.leave_requests where id=p_id for update;
 if not found then raise exception 'Request not found'; end if;
 if not (app_private.is_hr() or (public.current_role()='department_manager' and app_private.can_read_employee(r.employee_id))) then
 raise exception 'Permission denied'; end if;
 if r.employee_id=eid then raise exception 'Cannot approve or reject your own request'; end if;
 if r.status<>'pending' then raise exception 'Request already decided'; end if;
 if extract(year from r.start_date)<>extract(year from r.end_date) then raise exception 'Split legacy cross-year request first'; end if;
 select deduct_balance into deduct from public.leave_types where code=r.type;
 if not found then raise exception 'Map legacy leave type first'; end if;
 if p_approve and deduct then
 update public.leave_balances set used_days=used_days+r.days
 where employee_id=r.employee_id and leave_type=r.type and year=extract(year from r.start_date)::integer
 and entitled_days-used_days>=r.days;
 if not found then raise exception 'Insufficient leave balance'; end if;
 end if;
 update public.leave_requests set status=case when p_approve then 'approved' else 'rejected' end,
 approver_id=eid,reviewed_at=now(),decision_note=p_note where id=p_id returning * into r;
 return r;
end $$;
create or replace function public.cancel_leave(p_id uuid) returns public.leave_requests
language plpgsql security definer set search_path='' as $$
declare r public.leave_requests; begin
 update public.leave_requests set status='cancelled' where id=p_id and employee_id=public.current_employee_id() and status='pending' returning * into r;
 if not found then raise exception 'Only your pending request can be cancelled'; end if; return r;
end $$;
create or replace function public.mark_notification_read(p_id uuid) returns void
language plpgsql security definer set search_path='' as $$ begin
 update public.notifications set read_at=now() where id=p_id and user_id=auth.uid() and app_private.is_active();
end $$;

-- Explicit function privileges, including functions created by the original migration.
revoke all on function public.current_role(), public.current_employee_id(), public.check_in(), public.check_out(),
 public.request_leave(text,date,date,text),public.decide_leave(uuid,boolean,text),public.cancel_leave(uuid),public.mark_notification_read(uuid)
 from public,anon;
grant execute on function public.current_role(), public.current_employee_id(), public.check_in(), public.check_out(),
 public.request_leave(text,date,date,text),public.decide_leave(uuid,boolean,text),public.cancel_leave(uuid),public.mark_notification_read(uuid)
 to authenticated;
revoke all on all functions in schema app_private from public,anon,authenticated;
grant execute on function app_private.is_hr(),app_private.is_admin(),app_private.is_active(),app_private.can_read_employee(uuid) to authenticated;
revoke all on public.audit_logs from authenticated;
grant select on public.audit_logs to authenticated;

create index if not exists employees_manager_idx on public.employees(manager_id);
create index if not exists profiles_employee_idx on public.profiles(employee_id);
create index if not exists leave_employee_date_idx on public.leave_requests(employee_id,start_date,end_date);
create index if not exists contracts_employee_idx on public.contracts(employee_id);
create index if not exists payroll_employee_idx on public.payrolls(employee_id,period);
create index if not exists objectives_employee_idx on public.objectives(employee_id,cycle_id);
create index if not exists assignments_employee_idx on public.asset_assignments(employee_id);
create index if not exists notifications_user_idx on public.notifications(user_id,created_at desc);
create index if not exists audit_created_idx on public.audit_logs(created_at desc);

-- Private buckets. Employee files use <employee UUID>/<random UUID>.<ext>.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('hr-documents','hr-documents',false,10485760,array['application/pdf','image/jpeg','image/png']),
 ('hr-recruitment','hr-recruitment',false,10485760,array['application/pdf']),
 ('hr-reports','hr-reports',false,20971520,array['application/pdf','text/csv','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'])
 on conflict(id) do nothing;
drop policy if exists peopleops_storage_hr on storage.objects;
create policy peopleops_storage_hr on storage.objects for all to authenticated
 using(bucket_id in ('hr-documents','hr-recruitment','hr-reports') and app_private.is_hr())
 with check(bucket_id in ('hr-documents','hr-recruitment','hr-reports') and app_private.is_hr());
drop policy if exists peopleops_storage_self_read on storage.objects;
create policy peopleops_storage_self_read on storage.objects for select to authenticated
 using(bucket_id='hr-documents' and (storage.foldername(name))[1]=public.current_employee_id()::text);

insert into public.company_settings(id,company_name) values(true,'Chi Hung') on conflict do nothing;

insert into public.leave_types(code,name,paid,deduct_balance) values
 ('annual','Nghỉ phép năm',true,true),('unpaid','Nghỉ không lương',false,false),
 ('sick','Nghỉ ốm',false,false),('other','Nghỉ khác',false,false) on conflict(code) do nothing;
insert into public.work_shifts(code,name,start_time,end_time,break_minutes) values('OFFICE','Giờ hành chính','08:00','17:00',60) on conflict(code) do nothing;

-- Preserve existing department IDs and employee links; do not delete other legacy departments.
insert into public.departments(code,name,parent_id)
values('DIRECTOR','Giám đốc',null)
on conflict(code) do update set name=excluded.name,parent_id=null;
insert into public.departments(code,name,parent_id)
select d.code,d.name,p.id
from (values('HR','HR'),('SALES','Sales'),('ACCOUNTING','Kế toán')) as d(code,name)
cross join public.departments p where p.code='DIRECTOR'
on conflict(code) do update set name=excluded.name,parent_id=excluded.parent_id;

-- Import real staff without inventing email addresses. Existing emails and IDs are preserved.
alter table public.employees alter column work_email drop not null;
alter table public.employees add column if not exists end_date date;
alter table public.employees add column if not exists source_department text;
alter table public.employees add column if not exists employment_level smallint;
do $setup$ begin
 if not exists(select 1 from pg_constraint where conrelid='public.employees'::regclass and conname='employees_employment_dates') then
  alter table public.employees add constraint employees_employment_dates check(end_date is null or end_date>=start_date);
 end if;
end $setup$;

commit;
