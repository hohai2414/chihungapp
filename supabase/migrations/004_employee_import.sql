begin;
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
