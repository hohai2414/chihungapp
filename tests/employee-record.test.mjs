import test from 'node:test';
import assert from 'node:assert/strict';
import {mapEmployee} from '../src/employee-record.js';

test('keeps database UUID distinct from employee code and preserves missing contact data',()=>{
 const row={id:'uuid-employee',employee_code:'00123',full_name:'Nguyễn Văn An',work_email:null,phone:null,department_id:'d',position_id:'p',start_date:'2024-06-29',status:'terminated',source_department:'OP',end_date:'2025-06-06'};
 const result=mapEmployee(row,[{id:'d',name:'Sales'}],[{id:'p',name:'SUP'}]);
 assert.equal(result.id,'uuid-employee');assert.equal(result.code,'00123');assert.equal(result.email,'');assert.equal(result.phone,'');
 assert.equal(result.avatar,'VA');assert.equal(result.dept,'Sales');assert.equal(result.role,'SUP');assert.equal(result.status,'Đã nghỉ việc');
 assert.equal(result.sourceDepartment,'OP');assert.equal(result.endDate,'2025-06-06');assert.equal(result.start,'29/6/2024');
});
test('displays unknown relationships as missing instead of guessing a department or position',()=>{
 const result=mapEmployee({id:'x',employee_code:'x',full_name:'An',start_date:null,status:'active'},[],[]);
 assert.equal(result.dept,'Chưa phân bộ phận');assert.equal(result.role,'Chưa cập nhật');assert.equal(result.start,'—');assert.equal(result.avatar,'A');
});
