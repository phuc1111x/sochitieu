# Chính sách quyền riêng tư

**Sổ chi tiêu** · Có hiệu lực từ 02/11/2026

### 1. Về ứng dụng

Sổ chi tiêu là ứng dụng ghi chép chi tiêu cá nhân trên Android, do một nhà phát triển cá nhân làm ra. Ứng dụng chạy offline: dữ liệu của bạn nằm trên điện thoại của bạn. Nhà phát triển không có máy chủ riêng và không nhận bất kỳ dữ liệu nào của bạn.

Liên hệ: sanchykids@gmail.com

### 2. Dữ liệu ứng dụng xử lý

Ứng dụng chỉ xử lý những gì bạn tự nhập, cùng vài cài đặt của chính ứng dụng:

- **Khoản chi:** số tiền, danh mục, ngày, ghi chú và nguồn tiền đã dùng.
- **Nguồn tiền:** tên, loại (tiền mặt, ngân hàng, ví điện tử, thẻ tín dụng…), tổng hạn mức của thẻ tín dụng và ứng dụng thanh toán bạn gắn với nguồn đó.
- **Tiền vào, chuyển giữa các nguồn, điều chỉnh số dư.**
- **Cài đặt:** tự động sao lưu, chỉ sao lưu khi có Wi-Fi, thời điểm sao lưu gần nhất, đã kết nối Google Drive hay chưa và đã xem gợi ý vuốt hay chưa.

Ứng dụng không hỏi họ tên, số điện thoại, số tài khoản, số thẻ hay mật khẩu ngân hàng. Ứng dụng không truy cập vị trí, danh bạ, ảnh, camera, micro hay tin nhắn.

### 3. Dữ liệu được lưu ở đâu

Dữ liệu được lưu trên điện thoại của bạn, trong vùng lưu trữ riêng của ứng dụng mà các ứng dụng khác không đọc được. Ứng dụng không mã hoá thêm dữ liệu này, vì vậy bạn nên đặt khoá màn hình cho điện thoại. Dữ liệu được giữ trên máy cho đến khi bạn xoá (xem mục 8).

Dữ liệu chỉ rời khỏi điện thoại trong hai trường hợp ở mục 4 và mục 5.

### 4. Sao lưu lên Google Drive (tuỳ chọn)

- Chỉ diễn ra khi bạn tự kết nối Google Drive trong tab Sao lưu và đăng nhập tài khoản Google.
- Khi bạn đăng nhập, Google cho ứng dụng biết thông tin cơ bản của tài khoản: email, tên và ảnh đại diện. Ứng dụng chỉ hiện email trong tab Sao lưu để bạn biết đang dùng tài khoản nào. Ứng dụng không lưu và không gửi tên, email hay ảnh này đi đâu.
- Ngoài đăng nhập, ứng dụng chỉ xin một quyền với Drive: **drive.appdata**. Quyền này chỉ cho phép tạo, đọc, cập nhật và xoá tệp trong một thư mục ẩn dành riêng cho Sổ chi tiêu trong Drive của bạn. Ứng dụng không thấy, không đọc và không sửa các tệp khác trong Drive.
- Bản sao lưu là một tệp `sochitieu-backup.json` chứa các khoản chi, nguồn tiền, tiền vào, chuyển giữa các nguồn và điều chỉnh số dư. Mỗi lần sao lưu ghi đè lên tệp cũ; tệp được giữ cho đến khi bạn xoá (xem mục 8).
- Tệp được gửi thẳng từ điện thoại đến Google qua kết nối mã hoá (HTTPS), không đi qua máy chủ nào khác.
- Sao lưu chạy khi bạn bấm nút, hoặc tự động khi mở ứng dụng (tối đa một lần mỗi 24 giờ) nếu bạn bật. Nếu bạn chọn "chỉ khi có Wi-Fi", ứng dụng xem trạng thái mạng của điện thoại để biết đang dùng Wi-Fi hay không.
- Khi khôi phục, ứng dụng tải tệp sao lưu về và thay thế dữ liệu trên máy.
- Tệp sao lưu nằm trong tài khoản Google của bạn và tuân theo Chính sách quyền riêng tư của Google.
- Việc Sổ chi tiêu sử dụng thông tin nhận được từ API của Google tuân thủ Chính sách dữ liệu người dùng của Dịch vụ API Google (Google API Services User Data Policy), bao gồm các yêu cầu Sử dụng giới hạn (Limited Use).

### 5. Sao lưu của Android

Android có thể tự đưa dữ liệu của ứng dụng vào bản sao lưu thiết bị trong tài khoản Google của bạn, hoặc chuyển dữ liệu sang điện thoại mới (ví dụ bằng Samsung Smart Switch). Việc này do Android và Google thực hiện theo cài đặt trên điện thoại của bạn, Sổ chi tiêu không điều khiển. Bạn có thể tắt trong Cài đặt của điện thoại, ở mục Sao lưu hoặc Google.

### 6. Ứng dụng thanh toán đã cài

Khi bạn gắn một nguồn tiền với một ứng dụng thanh toán (ví dụ ứng dụng ngân hàng hoặc ví điện tử), Sổ chi tiêu đọc danh sách các ứng dụng có biểu tượng trên màn hình chính để bạn chọn. Danh sách này chỉ dùng trên máy, không được lưu và không được gửi đi.

Ứng dụng chỉ lưu tên gói (package name) của ứng dụng bạn chọn, cùng với nguồn tiền đó (và trong bản sao lưu Drive nếu bạn dùng). Khi bạn bấm "Lưu & mở", Sổ chi tiêu chỉ mở ứng dụng đó. Sổ chi tiêu không thấy và không ghi lại những gì bạn làm trong ứng dụng thanh toán.

### 7. Những điều ứng dụng không làm

- Không quảng cáo, không công cụ phân tích hay theo dõi, không tự gửi báo cáo lỗi.
- Không có máy chủ riêng. Không bán, không chia sẻ và không chuyển dữ liệu của bạn cho ai.
- Không kết nối với tài khoản ngân hàng và không thực hiện thanh toán.

### 8. Cách xoá dữ liệu

- **Một khoản chi:** mở khoản chi → Sửa → "Xoá khoản chi này".
- **Toàn bộ dữ liệu trên điện thoại:** gỡ ứng dụng, hoặc vào Cài đặt → Ứng dụng → Sổ chi tiêu → Lưu trữ → Xoá dữ liệu.
- **Thu hồi quyền truy cập Drive:** trong tab Sao lưu bấm "Ngắt kết nối / đổi tài khoản", hoặc vào https://myaccount.google.com/connections. Thu hồi quyền không xoá tệp sao lưu.
- **Tệp sao lưu trên Drive:** mở https://drive.google.com trên máy tính → Cài đặt → Quản lý ứng dụng → Sổ chi tiêu → Tuỳ chọn → Xoá dữ liệu ứng dụng ẩn.
- **Bản sao lưu của Android:** quản lý trong cài đặt sao lưu Google trên điện thoại.

### 9. Trẻ em

Ứng dụng không dành cho trẻ em dưới 13 tuổi. Nhà phát triển không thu thập dữ liệu của bất kỳ ai, kể cả trẻ em.

### 10. Thay đổi chính sách

Khi chính sách thay đổi, bản mới sẽ có trong ứng dụng và trên trang web, kèm ngày hiệu lực mới. Bản hiện hành luôn ở https://phuc1111x.github.io/sochitieu/privacy/

### 11. Liên hệ

Mọi câu hỏi về quyền riêng tư, xin gửi email tới sanchykids@gmail.com
