import fs from 'node:fs';
const root = new URL('../supabase/', import.meta.url);
let base = fs.readFileSync(new URL('migrations/001_init.sql', root), 'utf8');
let extra = fs.readFileSync(new URL('migrations/002_complete_hrm.sql', root), 'utf8');
// Only the final access model from migration 002 is installed.
base = base.replace(/^create policy .*;\r?\n/gm, '');
base = base.replace(/create type (\w+) as enum \(([^;]+)\);/gi, (_, name, labels) =>
 `do $setup$ begin\n if not exists(select 1 from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname='public' and t.typname='${name}') then\n create type public.${name} as enum (${labels});\n end if;\nend $setup$;`);
extra = extra.replace(/^begin;\r?\n/gm, '').replace(/^commit;\s*$/gm, '');
extra = extra.replace("('sick','Nghỉ ốm',false,false),('other','Nghỉ khác',false,false);", "('sick','Nghỉ ốm',false,false),('other','Nghỉ khác',false,false) on conflict(code) do nothing;");
extra = extra.replace("values('OFFICE','Giờ hành chính','08:00','17:00',60);", "values('OFFICE','Giờ hành chính','08:00','17:00',60) on conflict(code) do nothing;");
// Use the current organization for fresh installs and preserve existing employee links.
extra = extra.replace(/insert into public\.departments\(code,name\) values[\s\S]*?on conflict\(code\) do nothing;/, '');
const organization = fs.readFileSync(new URL('migrations/003_organization.sql', root), 'utf8')
 .replace(/^begin;\r?\n/gm, '').replace(/^commit;\s*$/gm, '');
const employeeImportSchema = fs.readFileSync(new URL('migrations/004_employee_import.sql', root), 'utf8')
 .replace(/^begin;\r?\n/gm, '').replace(/^commit;\s*$/gm, '');
let body = base + '\n' + extra + '\n' + organization;
body = body.replace(/\bcreate table (?!if not exists)/gi, 'create table if not exists ')
 .replace(/\bcreate (unique )?index (?!if not exists)/gi, (_, unique) => `create ${unique || ''}index if not exists `)
 .replace(/\badd column (?!if not exists)/gi, 'add column if not exists ')
 .replace(/\bcreate trigger /gi, 'create or replace trigger ');
body = body.replace(/alter table ([\w.]+) add constraint (\w+) ([^;]+);/gi, (_, table, name, definition) => {
 const qualified = table.includes('.') ? table : `public.${table}`;
 return `do $setup$ begin\n if not exists(select 1 from pg_constraint where conrelid='${qualified}'::regclass and conname='${name}') then\n alter table ${qualified} add constraint ${name} ${definition};\n end if;\nend $setup$;`;
});
body = body.replace(/^create policy (\w+) on ([\w.]+)/gm, (_, name, table) =>
 `drop policy if exists ${name} on ${table};\ncreate policy ${name} on ${table}`);
body += '\n' + employeeImportSchema;
// Reject a different attendance schema before installing functions or policies.
const preflight = `do $setup$
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
`;
const output = `-- Chi Hung / PeopleOps: rerunnable installation for this application's compatible schema.
-- Preserves business rows. Reinstalls application policies/functions/triggers.
-- Unrelated or structurally different tables need a reviewed migration.
begin;
set local search_path = public, extensions;
select pg_advisory_xact_lock(2414, 1001);
${preflight}${body}\ncommit;\n`;
fs.writeFileSync(new URL('FULL_SETUP.sql', root), output);
fs.writeFileSync(new URL('FIX_EXISTING_SETUP.sql', root), output);
console.log('Generated rerunnable FULL_SETUP.sql and FIX_EXISTING_SETUP.sql');

// Compatibility installer for the observed legacy table:
// attendance(id integer, person integer, shift integer, checkin text, checkout text).
// Never alter, rename, read or remap that table automatically.
const legacySafe = `-- USE THIS FILE when legacy public.attendance has person/shift/checkin/checkout.
-- Existing attendance and its policies are left untouched. No historical rows are imported.
-- New attendance table: public.peopleops_attendance.
-- New attendance RPCs: peopleops_check_in / peopleops_check_out.
` + output.replace(/\battendance\b/g, 'peopleops_attendance')
 .replace(/public\.check_in\(/g, 'public.peopleops_check_in(')
 .replace(/public\.check_out\(/g, 'public.peopleops_check_out(');
fs.writeFileSync(new URL('SETUP_KEEP_LEGACY_ATTENDANCE.sql', root), legacySafe);
console.log('Generated SETUP_KEEP_LEGACY_ATTENDANCE.sql');
