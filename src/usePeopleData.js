import {useCallback,useEffect,useRef,useState} from 'react';
import {supabase} from './supabase.js';
import {mapEmployee} from './employee-record.js';
export default function usePeopleData(user){
 const [state,setState]=useState({employees:[],departments:[],positions:[],profile:null,loading:true,error:''});
 const generation=useRef(0);
 const refresh=useCallback(async()=>{
  const request=++generation.current;setState(s=>({...s,loading:true,error:''}));
  try{
   const results=await Promise.all([
    supabase.from('employees').select('*').order('employee_code'),
    supabase.from('departments').select('*').order('name'),
    supabase.from('positions').select('*').order('name'),
    supabase.from('profiles').select('user_id,employee_id,role,active').eq('user_id',user.id).maybeSingle()
   ]);
   for(const result of results)if(result.error)throw result.error;
   const [employeeResult,departmentResult,positionResult,profileResult]=results;
   if(!profileResult.data?.active)throw new Error('Tài khoản chưa có hồ sơ hoạt động. Vui lòng liên hệ quản trị viên.');
   if(request===generation.current)setState({employees:employeeResult.data.map(row=>mapEmployee(row,departmentResult.data,positionResult.data)),departments:departmentResult.data,positions:positionResult.data,profile:profileResult.data,loading:false,error:''});
  }catch(error){if(request===generation.current)setState(s=>({...s,loading:false,error:error.message}));}
 },[user.id]);
 useEffect(()=>{refresh();return()=>{generation.current++;};},[refresh]);
 async function addEmployee(form){
  const department=state.departments.find(d=>d.name===form.get('dept'));
  if(!department)throw new Error('Bộ phận chưa được tạo trong Supabase.');
  const role=String(form.get('role')).trim();
  let position=state.positions.find(p=>p.department_id===department.id && p.name===role);
  if(!position){const {data,error}=await supabase.from('positions').insert({department_id:department.id,name:role}).select().single();if(error)throw error;position=data;}
  const {error}=await supabase.from('employees').insert({employee_code:`NV-${crypto.randomUUID().slice(0,12).toUpperCase()}`,full_name:String(form.get('name')).trim(),work_email:String(form.get('email')).trim()||null,phone:String(form.get('phone')).trim()||null,department_id:department.id,position_id:position.id,start_date:new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Ho_Chi_Minh',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date()),status:'probation'});
  if(error)throw error;await refresh();
 }
 async function removeEmployee(id){const {error}=await supabase.from('employees').delete().eq('id',id);if(error)throw error;await refresh();}
 return {...state,refresh,addEmployee,removeEmployee,canManage:['super_admin','hr_admin'].includes(state.profile?.role)};
}
