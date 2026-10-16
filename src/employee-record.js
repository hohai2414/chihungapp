export const statusLabels={probation:'Thử việc',active:'Đang làm việc',on_leave:'Đang nghỉ phép',terminated:'Đã nghỉ việc'};
const formatDate=value=>value ? new Intl.DateTimeFormat('vi-VN',{timeZone:'Asia/Ho_Chi_Minh'}).format(new Date(`${value}T00:00:00+07:00`)):'—';
export function mapEmployee(row,departments,positions){return{
 id:row.id,code:row.employee_code,name:row.full_name,email:row.work_email||'',phone:row.phone||'',
 dept:departments.find(d=>d.id===row.department_id)?.name||'Chưa phân bộ phận',
 role:positions.find(p=>p.id===row.position_id)?.name||'Chưa cập nhật',
 start:formatDate(row.start_date),startDate:row.start_date,status:statusLabels[row.status]||row.status,
 avatar:row.full_name.trim().split(/\s+/).slice(-2).map(word=>word[0]).join('').toUpperCase(),
 gender:row.gender||'—',sourceDepartment:row.source_department||'',endDate:row.end_date||null
};}
