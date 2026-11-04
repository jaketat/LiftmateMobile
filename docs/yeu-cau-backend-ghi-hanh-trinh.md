# Yêu cầu backend: lưu hành trình thực tế của chuyến

Người gửi: app mobile, 04/11/2026. Người làm: Jake (backend).

## Đã chốt
- **Nguồn đường đi:** điện thoại tài xế, không dùng hộp đen GPS.
- **Đoạn ghi đường đi:** từ mốc `Arrived` ở điểm bốc đầu tiên tới khi chuyến xong mọi điểm (`nextAction = null`).
- **Đoạn đi tới điểm bốc:** chỉ live khi app đang mở, như hiện nay (giữ vị trí mới nhất, không lưu đường).
- **Người xem:** ai có `Orders.View` xem được live trên bản đồ và xem lại sau, như BR-TRK-006.

**Cần anh Tiến xác nhận:** việc này đổi quyết định ngày 26/09 trong BR-TRK-003 ("chỉ giữ điểm mới nhất, không lưu lịch sử đường đi").

## App mobile đã đổi (chưa phát hành)
- Gọi `POST /me/trips/{tripId}/locations` như cũ. Trong đoạn ghi, app gửi **mọi điểm** đo được:
  - cách nhau khoảng 20 m, bỏ điểm sai số trên 200 m;
  - mỗi lô tối đa 100 điểm, theo nhịp `nextIntervalSeconds`.
- Mất sóng thì app giữ tối đa 3.000 điểm và gửi bù từng lô, cũ trước.
- App vẫn gửi khi chạy nền hoặc khóa màn hình. Các điểm đo lúc đó có `source = "Background"`; enum `LocationSource` đã có sẵn giá trị này.
- Trước đoạn ghi, app vẫn chỉ gửi một điểm mỗi nhịp, giống trước.

## Backend cần làm
1. **Bảng `trip_location_points`**
   - Cột: `dispatch_trip_id`, `company_id`, `user_id`, `recorded_at`, `received_at`, `latitude`, `longitude`, `accuracy_m`, `speed_kmh`, `heading`, `source`.
   - Chỉ mục `(dispatch_trip_id, recorded_at)`.
   - Giữ nguyên `trip_last_locations` cho bản đồ live.
2. **`SendTripLocations`**
   - Vẫn cập nhật `trip_last_locations` như cũ.
   - Lưu thêm vào bảng mới các điểm hợp lệ có `recorded_at` không sớm hơn mốc `Arrived` của điểm bốc đầu tiên.
   - Bỏ điểm trùng `(trip, recorded_at)` vì lô gửi bù có thể lặp.
   - Bỏ điểm nhảy bất thường: tốc độ suy ra so với điểm trước vượt 150 km/h.
   - Giữ nguyên các luật lọc điểm hiện có của BR-TRK-003.
3. **API đường đi: `GET /orders/{id}/dispatch-trips/{tripId}/path?after={recordedAt}`**
   - Quyền: `Orders.View`, giống `/track`.
   - Trả `points: [{ t, lat, lng, speedKmh }]`, sắp theo giờ đo. Có `after` thì chỉ trả phần mới, để màn live lấy dần mỗi 15 giây.
   - Kèm `milestones` (mốc có tọa độ) và `stops` (chỗ đứng yên trên 5 phút, server tự tính) để màn xem lại vẽ dòng thời gian.
   - Chuyến xong thì có thể trả `polyline` đã rút gọn (Douglas–Peucker khoảng 10 m) thay cho `points` để nhẹ.
4. **Dọn dữ liệu:** xóa điểm quá 90 ngày cùng vòng dọn của `DataRetentionCleanupService`.
5. **Điều khoản đồng ý vị trí**
   - Lên bản mới để tài xế đồng ý lại.
   - Lời mới: *"Từ lúc tới điểm bốc tới khi xong chuyến, app ghi đường xe chạy, kể cả khi khóa màn hình; điều phối và chủ xe xem được; lưu 90 ngày; rút lại lúc nào cũng được."*
6. **Tài liệu:** sửa BR-TRK-003, BR-TRK-006 và mục 5 của `slice-d-tracking-integration.md`.

## Ước lượng dữ liệu
- Khoảng 2.000 điểm cho 100 km (mỗi điểm cách nhau 20 m), cỡ 0,2–0,3 MB mỗi chuyến trước khi rút gọn.
- Xe đứng yên thì gần như không sinh điểm.
