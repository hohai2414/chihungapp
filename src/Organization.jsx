import React from 'react';
import { Building2, Users } from 'lucide-react';
import { organizationDepartments } from './organization.js';

export default function Organization({ employees, onViewEmployees }) {
  const count = name => employees.filter(employee => employee.dept === name).length;
  const departmentCard = department => (
    <article className={`org-department ${department.parentCode ? '' : 'org-director'}`} key={department.code}>
      <span className="org-icon"><Building2 aria-hidden="true" /></span>
      <span className="org-level">{department.parentCode ? 'Trực thuộc Giám đốc' : 'Cấp điều hành'}</span>
      <h2>Bộ phận {department.name}</h2>
      <p>{department.description}</p>
      <button className="secondary" onClick={() => onViewEmployees(department.name)}>
        <Users aria-hidden="true" /> {count(department.name)} nhân viên
      </button>
    </article>
  );
  return <>
    <div className="page-head"><div><p className="eyebrow">CƠ CẤU TỔ CHỨC</p><h1>Tổ chức</h1><p>4 bộ phận · HR, Sales và Kế toán trực thuộc Giám đốc.</p></div></div>
    <section className="org-chart" aria-label="Sơ đồ tổ chức công ty">
      <div className="org-root">{departmentCard(organizationDepartments[0])}</div>
      <div className="org-children">{organizationDepartments.slice(1).map(departmentCard)}</div>
    </section>
  </>;
}
