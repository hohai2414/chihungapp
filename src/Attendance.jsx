import React,{useCallback,useEffect,useMemo,useState} from 'react';
import {supabase} from './supabase.js';
import {attendanceLabels,cellLabel,monthBounds,totalHours} from './attendance-record.js';

export default function Attendance({employees}){
 const [month,setMonth]=useState('2025-06'),[records,setRecords]=useState([]),[loading,setLoading]=useState(true),[error,setError]=useState(''),[query,setQuery]=useState(''),[department,setDepartment]=useState('');
 const bounds=useMemo(()=>monthBounds(month),[month]);
 const load=useCallback(async()=>{
  const all=[];
  // Fetch all permitted records rather than relying on the server's default row limit.
  for(let offset=0;;offset+=1000){
   const {data,error}=await supabase.from('peopleops_attendance').select('id,employee_id,work_date,worked_hours,attendance_code,check_in,check_out,source_file,source_cell')
    .gte('work_date',bounds.start).lt('work_date',bounds.end).order('work_date').order('employee_id').range(offset,offset+999);
   if(error)throw error;all.push(...data);if(data.length<1000)break;
  }
  return all;
 },[bounds]);
 const [revision,setRevision]=useState(0);
 useEffect(()=>{let active=true;setLoading(true);setError('');setRecords([]);load().then(rows=>{if(active)setRecords(rows);}).catch(e=>{if(active)setError(e.message);}).finally(()=>{if(active)setLoading(false);});return()=>{active=false;};},[load,revision]);
 const visibleEmployees=employees.filter(e=>(!department||e.dept===department)&&`${e.code} ${e.name}`.toLowerCase().includes(query.toLowerCase()));
 const allowedIds=new Set(visibleEmployees.map(e=>e.id));
 const visibleRecords=records.filter(r=>allowedIds.has(r.employee_id));
 const byEmployee=new Map();for(const row of visibleRecords){if(!byEmployee.has(row.employee_id))byEmployee.set(row.employee_id,new Map());byEmployee.get(row.employee_id).set(row.work_date,row);}
 const hours=totalHours(visibleRecords);
 const days=Array.from({length:bounds.days},(_,i)=>`${month}-${String(i+1).padStart(2,'0')}`);
 return <>
  <div className="page-head"><div><p className="eyebrow">CHẤM CÔNG</p><h1>Bảng công tháng {month.slice(5)}/{month.slice(0,4)}</h1><p>Theo giờ làm và ký hiệu ghi nhận trong dữ liệu nguồn.</p></div><button className="secondary" disabled={loading} onClick={()=>setRevision(n=>n+1)}>Làm mới bảng công</button></div>
  <div className="toolbar attendance-toolbar"><label>Tháng<input aria-label="Tháng chấm công" type="month" value={month} onChange={e=>{if(e.target.value)setMonth(e.target.value);}}/></label><label>Bộ phận<select value={department} onChange={e=>setDepartment(e.target.value)}><option value="">Tất cả bộ phận</option>{[...new Set(employees.map(e=>e.dept))].map(name=><option key={name}>{name}</option>)}</select></label><label>Tìm nhân viên<input placeholder="Mã hoặc họ tên" value={query} onChange={e=>setQuery(e.target.value)}/></label></div>
  {error&&<div className="data-error" role="alert">Không tải được bảng công: {error}. Nếu chưa nhập dữ liệu, hãy chạy file nhập chấm công mới trong Supabase SQL Editor.</div>}
  {loading?<p role="status">Đang tải bảng công…</p>:!error&&<>
   <div className="dashboard-counts"><div className="dashboard-count"><span>Nhân viên có dữ liệu tháng</span><strong>{byEmployee.size}</strong></div><div className="dashboard-count"><span>Tổng giờ làm đã ghi nhận</span><strong>{hours??'—'}</strong></div><div className="dashboard-count"><span>Ô có giờ hoặc mã công</span><strong>{visibleRecords.filter(r=>r.worked_hours!=null||(r.attendance_code&&r.attendance_code!=='UNRECORDED')).length}</strong></div><div className="dashboard-count"><span>Ô trống trong nguồn</span><strong>{visibleRecords.filter(r=>r.attendance_code==='UNRECORDED').length}</strong></div></div>
   {!records.length&&<div className="data-status">Chưa có dữ liệu chấm công cho tháng này.</div>}
   <div className="table-card"><div className="table-wrap attendance-table"><table><caption className="sr-only">Bảng chấm công tháng {month}</caption><thead><tr><th scope="col">Nhân viên</th>{days.map(day=><th key={day} scope="col" className={[0,6].includes(new Date(`${day}T00:00:00Z`).getUTCDay())?'attendance-weekend':''}>{Number(day.slice(-2))}</th>)}<th scope="col">Giờ làm</th></tr></thead><tbody>{visibleEmployees.map(employee=>{const items=byEmployee.get(employee.id)||new Map();return <tr key={employee.id}><th scope="row"><strong>{employee.name}</strong><small>{employee.code} · {employee.dept}</small></th>{days.map(day=>{const row=items.get(day);const label=cellLabel(row);return <td key={day} className={row?.attendance_code==='WORK'?'attendance-work':label==='—'?'attendance-empty':'attendance-code'} title={row?`${attendanceLabels[row.attendance_code]||'Ghi nhận chấm công'}${row.source_cell?' · Ô '+row.source_cell:''}`:'Chưa có bản ghi'}>{label}</td>;})}<td className="attendance-total">{totalHours([...items.values()])??'—'}</td></tr>;})}</tbody></table></div>{!visibleEmployees.length&&<p className="empty">Không tìm thấy nhân viên phù hợp.</p>}</div>
  </>}
  <div className="attendance-legend">Số: giờ làm · P: phép · P/2: phép nửa ngày · KL: không lương · KL/2: không lương nửa ngày · B: bệnh · TS: thai sản · CT: công tác · OFF: ký hiệu OFF theo nguồn · —: chưa ghi nhận.</div><p className="attendance-note">Giờ làm chỉ cộng các ô có số; chưa bao gồm quy đổi phép hoặc tính tăng ca. Ô trống không tự coi là nghỉ hoặc vắng mặt.</p>
 </>;
}
