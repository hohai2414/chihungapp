begin;
do $schema$
declare
 target regclass := coalesce(to_regclass('public.peopleops_attendance'),to_regclass('public.attendance'));
 column_definition text;
begin
 if target is null or not exists(select 1 from pg_attribute where attrelid=target and attname='employee_id' and atttypid='uuid'::regtype and not attisdropped) then
  raise exception 'Install the compatible PeopleOps attendance schema first; the legacy attendance table is not modified.';
 end if;
 foreach column_definition in array array['worked_hours numeric(5,2)','attendance_code text','source_value text','source_file text','source_sheet text','source_cell text','imported_at timestamptz'] loop
  execute format('alter table %s add column if not exists %s',target,column_definition);
 end loop;
 if not exists(select 1 from pg_constraint where conrelid=target and conname='attendance_import_hours_range') then
  execute format('alter table %s add constraint attendance_import_hours_range check(worked_hours is null or worked_hours between 0 and 24)',target);
 end if;
 if not exists(select 1 from pg_constraint where conrelid=target and conname='attendance_import_code_valid') then
  execute format('alter table %s add constraint attendance_import_code_valid check(attendance_code is null or attendance_code in (''WORK'',''P'',''P/2'',''KL'',''KL/2'',''B'',''TS'',''CT'',''OFF'',''UNRECORDED''))',target);
 end if;
end $schema$;
commit;
