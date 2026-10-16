# SQL Supabase — Chi Hung / PeopleOps

> **Trường hợp đã xác nhận qua ảnh:** bảng `attendance` có `id/person/shift` là integer và `checkin/checkout` là text. Hãy dùng **SETUP_KEEP_LEGACY_ATTENDANCE.sql**, thay cho FULL_SETUP.sql hoặc FIX_EXISTING_SETUP.sql. Sao chép toàn bộ file vào một query mới và Run. Không cần chạy thêm file SQL khác sau đó.
>
> Bản này giữ nguyên bảng attendance cũ cùng dữ liệu và policy của nó; tạo bảng riêng `peopleops_attendance`. Chấm công qua RPC `peopleops_check_in` và `peopleops_check_out`; các RPC nghỉ phép vẫn giữ tên. Khi nối frontend, truy vấn `peopleops_attendance` thay vì `attendance`.
>
> Dữ liệu cũ chưa được chuyển sang bảng mới. Muốn chuyển phải có bảng ánh xạ `person` (integer) sang `employees.id` (UUID), biết định dạng/múi giờ của `checkin/checkout`, và đối chiếu ca làm. Không tự ép kiểu hoặc đoán liên kết.
>
> Đã thử trên PostgreSQL cục bộ với đúng 5 cột như ảnh, có dữ liệu và policy mẫu: cài thành công, chạy lại hai lần, giữ nguyên dữ liệu/policy cũ; RPC chấm công và duyệt phép hoạt động trên bảng mới. Chưa chạy trên Supabase thật.

## Chọn đúng cách cài

- **Gặp lỗi `relation "attendance" already exists`:** mở `FIX_EXISTING_SETUP.sql`, sao chép TOÀN BỘ nội dung vào một query mới trong Supabase SQL Editor và Run. Không chỉ chạy riêng một đoạn. File này và FULL_SETUP.sql có nội dung giống nhau.
- **Dự án Supabase mới hoặc đã cài bộ SQL của ứng dụng:** có thể chạy `FULL_SETUP.sql`. Bản hiện tại đã hỗ trợ chạy lại: bỏ qua bảng/type/cột/index/ràng buộc đã có, thay thế hàm/trigger/policy và không chèn trùng danh mục.
- **Dùng Supabase CLI cho dự án mới:** chạy migration 001 rồi 002 theo thứ tự. Hai migration gốc vẫn dành cho việc áp dụng một lần; không chạy lại chúng thủ công.
- Bản sửa giữ nguyên dữ liệu nghiệp vụ nhưng cài lại các chính sách quyền truy cập của ứng dụng trên 31 bảng. Những chính sách tùy chỉnh trên các bảng này sẽ bị thay bằng chính sách trong bộ SQL.
- Nếu bảng hiện có khác cấu trúc của ứng dụng, `IF NOT EXISTS` không tự chuyển đổi cấu trúc đó. Script kiểm tra trước các cột của attendance; các kiểu/cột/ràng buộc không tương thích khác vẫn có thể gây lỗi. Toàn bộ query nằm trong transaction để rollback nếu thất bại.
- Với dữ liệu cũ: tên loại phép chưa có trong `leave_types` cần được ánh xạ. FK `leave_type_fk` dùng NOT VALID để giữ nguyên dòng cũ; sau khi xử lý chạy `alter table public.leave_requests validate constraint leave_type_fk;`. Ràng buộc ngày/lương mới có thể từ chối dữ liệu cũ không hợp lệ.

## Phạm vi

Có 31 bảng: tổ chức, nhân viên, tài khoản, hợp đồng/phụ lục/tài liệu, ca làm, chấm công/điều chỉnh, lịch nghỉ, đơn phép/số dư, lương, chu kỳ đánh giá/OKR, tuyển dụng/phỏng vấn, tài sản/bàn giao, báo cáo, thông báo và nhật ký.

Các module ngoài danh sách nhân viên hiện chỉ có khung giao diện. Cấu trúc bổ sung là đề xuất triển khai cho những module đó. SQL không tự chuyển dữ liệu localStorage sang Supabase, không tự thêm đăng nhập, không tự nối giao diện hoặc tạo endpoint AI.

## Khởi tạo quản trị viên

1. Tạo user bằng Supabase Dashboard → Authentication → Users → Add user (hoặc Invite).
2. Dùng UUID user thực tế trong SQL Editor. Không dùng câu lệnh này trên trình duyệt hoặc đặt service role key trong frontend:

```sql
-- Thay UUID trước khi chạy. Profile được tự tạo từ trigger khi tạo user.
update public.profiles
set role = 'super_admin', active = true
where user_id = 'THAY_BANG_UUID_USER'::uuid;
```

Tài khoản Auth có sẵn trước khi cài cũng được tạo profile. Trigger không lấy role từ user metadata. Quản trị viên sau đó liên kết `profiles.employee_id` đến UUID nhân viên; liên kết này cần cho chấm công/nghỉ phép. HR chỉ được quản lý dữ liệu nghiệp vụ; chỉ super_admin được sửa role/profile.

## Nhập nhân viên và cấp phép

```sql
insert into public.positions(department_id,name)
select id,'Chuyên viên nhân sự' from public.departments where code='HR';

-- Dữ liệu ví dụ; thay bằng thông tin thực tế.
insert into public.employees(employee_code,full_name,work_email,department_id,start_date,status)
select 'NV-001','Nhân viên ví dụ','nhanvien@example.com',id,current_date,'active'
from public.departments where code='HR';

-- Thay UUID user và mã nhân viên trước khi liên kết.
-- update public.profiles set employee_id=(select id from public.employees where employee_code='NV-001')
-- where user_id='UUID_USER'::uuid;

insert into public.leave_balances(employee_id,leave_type,year,entitled_days)
select id,'annual',extract(year from current_date)::integer,12
from public.employees where employee_code='NV-001'
on conflict do nothing;
```

12 ngày ở ví dụ là giá trị minh họa; cấu hình theo chính sách thực tế. Script chỉ seed phòng ban, ca làm và danh mục nghỉ; không tự tạo nhân viên, mật khẩu, lương hay tài khoản quản trị.

## Quyền truy cập

- Chưa đăng nhập: không được đọc/ghi bảng ứng dụng.
- Employee: xem hồ sơ của mình, hợp đồng, tài liệu, bảng lương đã duyệt/trả, mục tiêu, đánh giá đã công bố và tài sản đã cấp.
- Department manager: thêm quyền đọc hồ sơ và chấm công/phép/mục tiêu/cấp phát của nhân viên có `manager_id` trỏ trực tiếp đến mình; có thể duyệt đơn phép của họ. Không tự động cấp quyền cho toàn bộ phòng ban hoặc lương của cấp dưới.
- HR admin/super admin: quản lý nghiệp vụ. Chỉ super admin xem audit và sửa tài khoản/cấu hình công ty.
- Nhân viên dùng các RPC bên dưới; không được tự sửa lương, thời gian công hoặc trạng thái duyệt.
- HR là vai trò tin cậy, có quyền chỉnh trực tiếp dữ liệu, bao gồm đơn phép và số dư. Luồng ứng dụng phải gọi RPC để duyệt phép nhằm cập nhật số dư đồng bộ. Chỉnh tay phải đối chiếu số dư.

## RPC gọi sau khi đăng nhập

```javascript
await supabase.rpc('check_in');
await supabase.rpc('check_out');
await supabase.rpc('request_leave', {
  p_type: 'annual', p_start: '2026-10-19', p_end: '2026-10-20', p_reason: 'Việc cá nhân'
});
await supabase.rpc('decide_leave', { p_id: leaveId, p_approve: true, p_note: 'Đồng ý' });
await supabase.rpc('cancel_leave', { p_id: leaveId });
await supabase.rpc('mark_notification_read', { p_id: notificationId });
```

Phép nguyên ngày tính thứ Hai đến thứ Sáu, trừ `holidays`; đơn qua năm phải tách. Duyệt kiểm tra số dư và khóa dòng để tránh trừ trùng. Chỉ hủy đơn đang chờ, chưa hỗ trợ hoàn phép đã duyệt. Không tự duyệt đơn của mình.

Chấm công theo giờ máy chủ và ngày Việt Nam, một bản ghi/ngày. Chưa hỗ trợ ca qua đêm, GPS, tính đi muộn/tăng ca tự động. Các cột phút cần quy trình HR/backend riêng. Yêu cầu điều chỉnh công có bảng lưu nhưng chưa có RPC nhân viên gửi/duyệt; HR có thể xử lý qua backend.

Bảng lương chỉ lưu các số tiền đã được tính và tính net_salary từ các cột. Chưa có bộ máy thuế, bảo hiểm, khóa bảng công hoặc quy trình duyệt chi trả. Bàn giao tài sản giới hạn một người giữ/tài sản; backend phải đồng bộ `assets.status` trong transaction. Mục tiêu và tuyển dụng hiện HR quản lý, nhân viên có quyền đọc theo chính sách.

## Lưu tệp

Ba bucket private: `hr-documents`, `hr-recruitment`, `hr-reports`. Không tạo public URL cho tài liệu HR.

Tệp hồ sơ/hợp đồng đặt ở `hr-documents/<employee UUID>/<random UUID>.pdf`. HR upload; nhân viên chỉ đọc thư mục UUID của mình. CV và báo cáo chỉ HR truy cập. Tham chiếu đường dẫn trong bảng không tự upload/xóa object. Không đưa tài liệu nội bộ chỉ dành HR vào thư mục nhân viên, vì nhân viên đọc được toàn bộ thư mục của họ.

## Kiểm tra sau cài

```sql
select tablename, rowsecurity from pg_tables
where schemaname='public' order by tablename;
select * from public.departments order by code;
select * from public.leave_types;
select id,public from storage.buckets
where id in ('hr-documents','hr-recruitment','hr-reports');
```

Kiểm tra RLS bằng JWT của các tài khoản khác vai trò trên staging; SQL Editor chạy với quyền postgres nên không đại diện quyền người dùng. Kiểm tra nhân viên A không đọc được lương/tài liệu B, không thay role; manager không duyệt đơn mình; request lặp không trừ phép hai lần.

Tham khảo chính thức: https://supabase.com/docs/guides/database/postgres/row-level-security ; https://supabase.com/docs/guides/database/functions ; https://supabase.com/docs/guides/storage/security/access-control

## Kết quả kiểm tra cục bộ

Đã thực thi FULL_SETUP.sql trên PostgreSQL chạy trong PGlite: tạo đủ 31 bảng và chạy qua các kiểm tra: nhân viên chỉ đọc hồ sơ mình, không tự nâng role, check-in/check-out, gửi đơn, HR duyệt, trừ đúng 2 ngày và chặn duyệt lặp.

Môi trường kiểm tra mô phỏng auth.users, auth.uid(), các role và bảng Storage; bỏ câu lệnh cài pgcrypto do runtime thử nghiệm không đóng gói extension này. Đây chưa phải kiểm thử trên một dự án Supabase thật. Cần kiểm tra JWT/RLS và upload/download trên staging.

Đã sửa tên hàm `current_role` ở migration 001 thành `public.current_role` để tránh xung đột với từ khóa PostgreSQL. Các lời gọi trong policy cũng được ghi rõ schema.

## Kiểm tra bản sửa lỗi bảng đã tồn tại

Đã kiểm tra PostgreSQL cục bộ: cài mới; nâng từ migration 001; chạy lại hai lần khi đã có dữ liệu nhân viên/chấm công/đơn phép. Dữ liệu chấm công và số dư phép được giữ nguyên, ca làm mẫu không bị nhân đôi. Chưa thực thi trên dự án Supabase của người dùng.

Bản SQL được tạo lại từ migration gốc bằng `node scripts/build-sql-setup.mjs`.

