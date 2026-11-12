# EAMT5 — XAU Risk Management

Expert Advisor (MQL5) cho MetaTrader 5, **chỉ áp dụng cho XAUUSD**. EA không tự vào lệnh; nó theo dõi các lệnh bạn (hoặc EA khác) mở và **tự đặt Take Profit** để kiểm soát rủi ro khi khối lượng lớn.

## Chức năng

Mỗi khi có lệnh mới được mở (deal `DEAL_ENTRY_IN`), EA kiểm tra theo thứ tự:

| Rule | Điều kiện | Hành động |
|------|-----------|-----------|
| 2 | Tổng volume các lệnh XAUUSD đang mở (đã gồm lệnh mới) **> `TotalVolumeLimit`** (mặc định 0.4 lot) | Đặt TP cho **lệnh vừa mở**, kể cả khi volume nhỏ |
| 1 | Volume lệnh mới **> `ThresholdVolume`** (mặc định 0.05 lot; đúng 0.05 thì không đặt) | Đặt TP cho lệnh vừa mở |

- TP = giá mở ± `TpPips` (mặc định 15 pip; 1 pip = 10 point). Buy: cộng, Sell: trừ.
- Chỉ tác động lên lệnh mới; các lệnh cũ giữ nguyên.
- Lệnh đã có TP (đặt thủ công) sẽ **không bị ghi đè**; SL hiện có được giữ nguyên.
- So sánh số thực có sai số (`EPS`) để tránh lỗi làm tròn (vd 0.1×4 vs 0.4).

## Dashboard

Panel nhỏ trên chart: tổng volume / giới hạn (xanh → vàng khi ≥75% → đỏ khi vượt), số lệnh đang mở, và cấu hình TP.

## Inputs

| Input | Mặc định | Ý nghĩa |
|-------|----------|---------|
| `EA_Symbol` | XAUUSD | Symbol áp dụng (đổi nếu broker đặt tên khác, vd `XAUUSDm`) |
| `ThresholdVolume` | 0.05 | Rule 1: ngưỡng volume mỗi lệnh |
| `TotalVolumeLimit` | 0.4 | Rule 2: ngưỡng tổng volume |
| `TpPips` | 15 | Khoảng cách TP (pip) |
| `MagicNumber` | 0 | 0 = xử lý mọi lệnh; khác 0 = chỉ lệnh có magic này |
| `VerboseLog` | true | Log chi tiết vào tab Experts |
| `PanelX` / `PanelY` | 10 / 20 | Vị trí panel |

## Cài đặt

1. Chép `XAU Risk Management.mq5` vào `MQL5/Experts/` (MT5: *File → Open Data Folder*).
2. Biên dịch trong MetaEditor (F7).
3. Gắn EA lên chart XAUUSD và bật **Algo Trading**.

## Lưu ý

- Xử lý hoàn toàn trong `OnTradeTransaction` (có `Sleep(300)` chờ position vào pool); `OnTick` chỉ cập nhật dashboard.
- Chưa được backtest/kiểm thử trên tài khoản thật — hãy thử trên demo trước.
