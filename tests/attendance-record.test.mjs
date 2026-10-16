import test from 'node:test';
import assert from 'node:assert/strict';
import {cellLabel,monthBounds,totalHours} from '../src/attendance-record.js';
test('month boundaries include leap days and roll into the next year',()=>{
 assert.deepEqual(monthBounds('2024-02'),{start:'2024-02-01',end:'2024-03-01',days:29});
 assert.deepEqual(monthBounds('2025-06'),{start:'2025-06-01',end:'2025-07-01',days:30});
 assert.equal(monthBounds('2025-12').end,'2026-01-01');assert.throws(()=>monthBounds('2025-13'));
});
test('blank, leave, and a numeric zero retain distinct meanings',()=>{
 assert.equal(cellLabel(null),'—');assert.equal(cellLabel({attendance_code:'UNRECORDED',worked_hours:null}),'—');
 assert.equal(cellLabel({attendance_code:'P',worked_hours:null}),'P');assert.equal(cellLabel({attendance_code:'KL',worked_hours:null}),'KL');
 assert.equal(cellLabel({attendance_code:'WORK',worked_hours:0}),'0');
 assert.equal(totalHours([{worked_hours:null,attendance_code:'P'}]),null);
 assert.equal(totalHours([{worked_hours:0}]),0);
 assert.equal(totalHours([{worked_hours:'8.00'},{worked_hours:4},{worked_hours:null,attendance_code:'P/2'}]),12);
});
