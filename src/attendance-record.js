export const attendanceLabels={WORK:'Giờ làm',P:'Phép','P/2':'Phép nửa ngày',KL:'Không lương','KL/2':'Không lương nửa ngày',B:'Bệnh',TS:'Thai sản',CT:'Công tác',OFF:'OFF theo nguồn',UNRECORDED:'Chưa ghi nhận'};
export function monthBounds(month){
 if(!/^\d{4}-(0[1-9]|1[0-2])$/.test(month))throw new Error('Tháng không hợp lệ');
 const [year,number]=month.split('-').map(Number);
 return {start:`${month}-01`,end:new Date(Date.UTC(year,number,1)).toISOString().slice(0,10),days:new Date(Date.UTC(year,number,0)).getUTCDate()};
}
export function cellLabel(record){
 if(!record)return '—';
 if(record.worked_hours!==null && record.worked_hours!==undefined)return String(Number(record.worked_hours));
 if(record.attendance_code && record.attendance_code!=='UNRECORDED')return record.attendance_code;
 return record.check_in?'Vào ca':'—';
}
export function totalHours(records){const numbers=records.filter(r=>r.worked_hours!==null && r.worked_hours!==undefined).map(r=>Number(r.worked_hours));return numbers.length?numbers.reduce((sum,n)=>sum+n,0):null;}
