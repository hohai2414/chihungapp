# Chatbot Chi Hung AI

Sau đăng nhập, nút Trợ lý AI nằm ở góc dưới bên phải. Hỗ trợ tiếng Việt, hướng dẫn sử dụng ứng dụng và số nhân viên tổng hợp theo phạm vi RLS. Không tự sửa dữ liệu, không đọc hồ sơ cá nhân/lương/ngân hàng, không có tìm kiếm web. Tin nhắn do người dùng gửi được chuyển tới OpenAI; tránh đưa thông tin nhạy cảm vào câu hỏi. Lịch sử chỉ trong bộ nhớ phiên của giao diện, không lưu database.

Vercel → chihungapp → Settings → Environment Variables:

- OPENAI_API_KEY: khóa mới, loại Secret/Sensitive, Production. Không thêm tiền tố VITE_. Không đưa khóa vào Git hoặc frontend.
- OPENAI_MODEL: tùy chọn, mặc định gpt-5.4-mini; có thể đổi sang model dự án OpenAI của bạn được phép dùng.
- VITE_SUPABASE_URL và VITE_SUPABASE_PUBLISHABLE_KEY: giữ cấu hình đúng dự án hiện có. Máy chủ cũng dùng hai giá trị này để xác minh phiên và truy vấn qua RLS; không cần service_role.

Lưu rồi Redeploy. Thu hồi khóa đã gửi trong cuộc trò chuyện và tự dán khóa mới trực tiếp vào Vercel. Code không lưu khóa đã gửi.

Endpoint POST /api/chat xác thực token bằng Supabase getUser và kiểm tra profile active, giới hạn độ dài lịch sử, timeout gọi AI và trả thông báo lỗi không chứa khóa. Giới hạn 10 lần/phút/tài khoản trong mỗi instance là giới hạn cơ bản, không phải quota dùng chung giữa nhiều serverless instance. Cấu hình hạn mức chi phí trong dự án OpenAI nếu cần kiểm soát sử dụng toàn hệ thống.

API Responses dùng store:false. Các kiểm tra cục bộ dùng phản hồi giả, không gọi API trả phí và không xác minh khóa/model của tài khoản thật. Sau khi thêm khóa mới, kiểm tra câu hỏi ngắn trên Production. Nếu lỗi quota/model, kiểm tra quyền model, hạn mức và thanh toán trong dự án OpenAI.

Tài liệu OpenAI chính thức: https://developers.openai.com/api/docs/quickstart
