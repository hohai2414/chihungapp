begin;
-- Preserve existing department IDs and employee links; do not delete other legacy departments.
insert into public.departments(code,name,parent_id)
values('DIRECTOR','Giám đốc',null)
on conflict(code) do update set name=excluded.name,parent_id=null;
insert into public.departments(code,name,parent_id)
select d.code,d.name,p.id
from (values('HR','HR'),('SALES','Sales'),('ACCOUNTING','Kế toán')) as d(code,name)
cross join public.departments p where p.code='DIRECTOR'
on conflict(code) do update set name=excluded.name,parent_id=excluded.parent_id;
commit;
