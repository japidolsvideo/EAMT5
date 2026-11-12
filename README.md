# EAMT5

Bộ EA MetaTrader 5 (MQL5) cho XAUUSD.

| File | Mô tả |
|------|-------|
| `XAU Risk Management.mq5` | Tự đặt TP cho lệnh mới theo volume (xem mục 1) |
| `3EMA_NoDashBoard_Original.mq5` | EA vào lệnh 3 EMA M5 + lọc H1, v3.02, không dashboard (xem mục 2) |
| `3EMA_Dashboard_Original.mq5` | Như trên, v4.00, có dashboard debug (xem mục 2) |
| `TelegramAlertEA.mq5` | Gửi cảnh báo Telegram khi mở/đóng lệnh, chạm TP/SL, dời SL (xem mục 3) |

## 🛡️ 1. XAU Risk Management ⭐

Expert Advisor (MQL5) cho MetaTrader 5, **chỉ áp dụng cho XAUUSD**. EA không tự vào lệnh; nó theo dõi các lệnh bạn (hoặc EA khác) mở và **tự đặt Take Profit** để kiểm soát rủi ro khi khối lượng lớn.

### Chức năng

Mỗi khi có lệnh mới được mở (deal `DEAL_ENTRY_IN`), EA kiểm tra theo thứ tự:

| Rule | Điều kiện | Hành động |
|------|-----------|-----------|
| 2 | Tổng volume các lệnh XAUUSD đang mở (đã gồm lệnh mới) **> `TotalVolumeLimit`** (mặc định 0.4 lot) | Đặt TP cho **lệnh vừa mở**, kể cả khi volume nhỏ |
| 1 | Volume lệnh mới **> `ThresholdVolume`** (mặc định 0.05 lot; đúng 0.05 thì không đặt) | Đặt TP cho lệnh vừa mở |

- TP = giá mở ± `TpPips` (mặc định 15 pip; 1 pip = 10 point). Buy: cộng, Sell: trừ.
- Chỉ tác động lên lệnh mới; các lệnh cũ giữ nguyên.
- Lệnh đã có TP (đặt thủ công) sẽ **không bị ghi đè**; SL hiện có được giữ nguyên.
- So sánh số thực có sai số (`EPS`) để tránh lỗi làm tròn (vd 0.1×4 vs 0.4).

### Dashboard

Panel nhỏ trên chart: tổng volume / giới hạn (xanh → vàng khi ≥75% → đỏ khi vượt), số lệnh đang mở, và cấu hình TP.

Dòng thứ 3 (chữ nhỏ) là **giá thanh lý ước tính** và % khoảng cách tới giá hiện tại. Tính từ equity, margin, ngưỡng stop-out của broker và net volume XAU (buy − sell): `giá = giá hiện tại + (ngưỡng stop-out − equity) / (net volume × contract size)`. Màu xanh khi cách xa ≥ 8%, vàng 3–8%, đỏ < 3%. Hiện `—` khi không có lệnh hoặc net volume = 0. Đây là ước tính: giả định margin không đổi và chỉ giá XAU thay đổi.

### Inputs

| Input | Mặc định | Ý nghĩa |
|-------|----------|---------|
| `EA_Symbol` | XAUUSD | Symbol áp dụng (đổi nếu broker đặt tên khác, vd `XAUUSDm`) |
| `ThresholdVolume` | 0.05 | Rule 1: ngưỡng volume mỗi lệnh |
| `TotalVolumeLimit` | 0.4 | Rule 2: ngưỡng tổng volume |
| `TpPips` | 15 | Khoảng cách TP (pip) |
| `MagicNumber` | 0 | 0 = xử lý mọi lệnh; khác 0 = chỉ lệnh có magic này |
| `VerboseLog` | true | Log chi tiết vào tab Experts |
| `PanelX` / `PanelY` | 10 / 20 | Vị trí panel |

### Cài đặt

1. Chép `XAU Risk Management.mq5` vào `MQL5/Experts/` (MT5: *File → Open Data Folder*).
2. Biên dịch trong MetaEditor (F7).
3. Gắn EA lên chart XAUUSD và bật **Algo Trading**.

### Lưu ý

- Xử lý hoàn toàn trong `OnTradeTransaction` (có `Sleep(300)` chờ position vào pool); `OnTick` chỉ cập nhật dashboard.
- Chưa được backtest/kiểm thử trên tài khoản thật — hãy thử trên demo trước.

## 🛡️ 2. 3EMA M5 Buy/Sell (XAUUSD, M5) ⭐

EA tự vào lệnh bằng **Buy Stop / Sell Stop**, xử lý một lần mỗi nến M5 mới. Hai file có cùng chiến lược.

### Điều kiện vào lệnh

**Buy** (Sell là chiều ngược lại), đọc trên nến M5 vừa đóng (bar #1):

1. H1: giá > EMA nhanh (8) và EMA nhanh > EMA chậm (21).
2. M5: Close > EMA1 (8), EMA1 > EMA2 (13), EMA2 > EMA3 (21).
3. Low nến tín hiệu chạm EMA1 (Sell: High chạm EMA1).
4. Entry = đỉnh cao nhất `InpLookbackBars` nến trước + `InpEntryPips`; phải cao hơn Ask (Sell: đáy thấp nhất − pip, thấp hơn Bid).
5. SL = Low nến tín hiệu − `InpSLPips`; TP = Entry + `InpRR` × khoảng SL.
6. Lot tính theo `InpRiskPercent` % balance.

### Quản lý lệnh

- **Dời SL về hoà vốn** (`InpSetSLatBE`): khi lãi đạt 1R/2R/3R thì dời SL tới entry ± `InpBEOffsetPips`.
- **Đóng trước cuối tuần**: đóng các lệnh đang chạy 1/2/3 giờ trước `InpFridayCloseHour` thứ Sáu, không đặt lệnh mới trong khung đó (pending giữ nguyên).
- **Giới hạn**: `InpMaxPendingOrders` (pending) và `InpMaxRunningOrders` (đang chạy), tách riêng.
- Tuỳ chọn: hết hạn pending sau N nến, lọc phiên London/NY, chọn chỉ Buy / chỉ Sell / cả hai.

### Khác biệt giữa hai file

| | `3EMA_Dashboard_Original` (v4.00) | `3EMA_NoDashBoard_Original` (v3.02) |
|---|---|---|
| Dashboard trên chart | Có: trạng thái chung, xu hướng H1 (UPTREND/DOWNTREND/SIDEWAY), PASS/FAIL từng điều kiện | Không |
| Chặn trùng pending | **Không**: có thể đặt thêm pending mỗi nến khi điều kiện còn đúng | Có: tối đa 1 Buy Stop và 1 Sell Stop chờ |
| Log lý do bỏ qua | Hiện trên dashboard | `Print("SKIP: ...")` vào tab Experts |

Lưu ý với bản Dashboard: giới hạn pending mặc định là 10000 nên gần như không chặn được việc đặt chồng; session và số lệnh được tính lại theo chu kỳ `InpDashRefreshSec` (mặc định 10 giây) nên có thể cũ khi có nến mới. Muốn chạy thật nên dùng bản NoDashboard, hoặc giảm `InpMaxPendingOrders`.

Chưa backtest — hãy thử trên demo trước.

## 🛡️ 3. TelegramAlertEA ⭐

EA không giao dịch; nó theo dõi tài khoản và **gửi tin nhắn Telegram** mỗi khi có sự kiện lệnh (v1.10).

### Các cảnh báo

| Sự kiện | Input bật/tắt | Nội dung tin nhắn |
|---------|---------------|-------------------|
| Lệnh mới mở | `InpAlertOpen` | Loại Buy/Sell, symbol, volume, giá, SL, TP, ticket |
| Lệnh đóng | `InpAlertClose` | Lý do (SL, TP, đóng tay, EA đóng…), symbol, volume, giá đóng, lợi nhuận ròng (gồm commission + swap), balance |
| Chạm Take Profit | `InpAlertTP` | Như trên, tin riêng "Take Profit Hit" |
| Đổi Stop Loss | `InpAlertSL` | SL cũ → SL mới, ghi chú nếu là trailing |

Khi khởi động EA gửi thêm một tin kiểm tra kết nối (số tài khoản, balance).

### Hướng dẫn sử dụng

1. **Tạo bot**: chat với [@BotFather](https://t.me/BotFather) → `/newbot` → lấy **Bot Token**.
2. **Lấy Chat ID**: nhắn một tin cho bot (hoặc thêm bot vào group/channel và cho quyền gửi tin), rồi mở `https://api.telegram.org/bot<TOKEN>/getUpdates` và đọc `chat.id` (group/channel thường là số âm, dạng `-100…`).
3. **Cho phép WebRequest trong MT5**: *Tools → Options → Expert Advisors* → tick *Allow WebRequest for listed URL* → thêm `https://api.telegram.org` → OK, **khởi động lại MT5**.
4. Chép `TelegramAlertEA.mq5` vào `MQL5/Experts/`, biên dịch (F7).
5. Gắn EA lên **một chart bất kỳ** (một chart là đủ, EA theo dõi toàn tài khoản), bật **Algo Trading**.
6. Nhập `InpBotToken` và `InpChatID`. Thiếu một trong hai, EA báo lỗi và không chạy.
7. Kiểm tra Telegram có tin "TelegramAlertEA Started". Không có thì xem tab *Experts*: lỗi `4014` là chưa thêm URL ở bước 3; HTTP `401` sai token; `400` sai Chat ID; `403` bot chưa được thêm vào group hoặc bị chặn.

### Inputs

| Input | Mặc định | Ý nghĩa |
|-------|----------|---------|
| `InpBotToken` | rỗng | Token của bot |
| `InpChatID` | rỗng | ID người/group/channel nhận tin |
| `InpAlertOpen` / `InpAlertClose` / `InpAlertTP` / `InpAlertSL` | true | Bật/tắt từng loại cảnh báo |
| `InpDebugMode` | true | Log chi tiết vào tab Experts |

### Lưu ý

- **Đặt `InpDebugMode = false` khi dùng thật**: chế độ debug in URL gọi API, trong đó có Bot Token, vào log Experts. Không chia sẻ log khi còn bật debug.
- Mục "Ticket" trong tin báo mở lệnh là ticket của deal, không phải ticket của position.
- Cảnh báo đổi SL có thể **không hoạt động**: `CheckNewPositions()` gọi `InitSLTracker()` mỗi lần chạy, ghi đè SL đã lưu bằng SL hiện tại trước khi `CheckSLChanges()` so sánh. Chưa kiểm thử trên MT5.
- Mở lệnh có thể bị báo trùng, vì được phát hiện cả bằng `OnTradeTransaction` lẫn polling.
- Chưa backtest/kiểm thử — hãy thử trên demo trước.
