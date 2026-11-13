//+------------------------------------------------------------------+
//|                                         XAU Risk Management.mq5 |
//|                                                                  |
//|  Áp dụng cho XAUUSD và BTCUSD (mỗi cặp có thông số riêng)      |
//|  Rule 1: lệnh mới có volume > ThresholdVolume (0.05) → set TP   |
//|          (đúng 0.05 vẫn OK, từ 0.06 trở lên thì set TP)        |
//|  Rule 2: tổng volume (đã gồm lệnh mới) > TotalVolumeLimit (0.4) |
//|          → set TP lệnh mới nhất, kể cả khi lệnh đó vol nhỏ      |
//|          (chỉ lệnh vừa mở, các lệnh cũ không thay đổi)          |
//+------------------------------------------------------------------+
#property copyright "XAU Risk Management"
#property version   "1.40"
#property strict

//--- Inputs
input string   EA_Symbol         = "XAUUSD";  // Symbol áp dụng
input double   ThresholdVolume   = 0.05;       // Rule 1: ngưỡng volume/lệnh (lot)
input double   TotalVolumeLimit  = 0.4;        // Rule 2: ngưỡng tổng volume (lot)
input double   TpPips            = 15.0;       // TP (pip)
input string   BTC_Symbol        = "BTCUSD";   // BTC: symbol ("" = tắt BTC)
input double   BTC_ThresholdVolume = 0.1;      // BTC Rule 1: ngưỡng volume/lệnh (lot)
input double   BTC_TotalVolumeLimit = 0.4;     // BTC Rule 2: ngưỡng tổng volume (lot)
input double   BTC_TpPips        = 10.0;       // BTC: TP (pip)
input int      MagicNumber       = 0;          // Magic Number (0 = tất cả)
input bool     VerboseLog        = true;       // Log chi tiết
input int      PanelX            = 10;         // Panel vị trí X
input int      PanelY            = 20;         // Panel vị trí Y

//--- Globals
bool     g_btcOn    = false;   // BTC được bật và symbol hợp lệ

#define PFX "XAURM_"
#define EPS 1e-8   // sai số so sánh số thực (tránh lỗi 0.1+0.1+0.1+0.1 > 0.4)

//+------------------------------------------------------------------+
int OnInit()
{
   if(!SymbolInfoInteger(EA_Symbol, SYMBOL_SELECT))
   {
      Print("[XAU RM] Symbol ", EA_Symbol, " không tìm thấy.");
      return INIT_FAILED;
   }
   g_btcOn = (BTC_Symbol != "" && SymbolSelect(BTC_Symbol, true));
   if(BTC_Symbol != "" && !g_btcOn)
      Print("[XAU RM] Symbol ", BTC_Symbol, " không tìm thấy → tắt quản lý BTC.");

   CreateDashboard();
   UpdateDashboard();

   Print("[XAU RM] v1.40 Started | Symbol:", EA_Symbol,
         " | ThreshVol:", ThresholdVolume,
         " | TotalLim:", TotalVolumeLimit,
         " | TP:", TpPips, "pip");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   DeleteDashboard();
   Print("[XAU RM] Stopped. Reason:", reason);
}

//+------------------------------------------------------------------+
// OnTick: CHỈ cập nhật dashboard, KHÔNG xử lý TP
//+------------------------------------------------------------------+
void OnTick()
{
   UpdateDashboard();
}

//+------------------------------------------------------------------+
// OnTradeTransaction: điểm xử lý DUY NHẤT
// Mỗi lần có deal mới → xác định đúng position ticket vừa mở
// → quyết định set TP hay không dựa trên rule
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
   // Chỉ quan tâm deal IN (mở lệnh mới) trên đúng symbol
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   // Chọn thông số theo symbol của deal
   double thrVol, totLim, tpPips;
   if(trans.symbol == EA_Symbol)
   {
      thrVol = ThresholdVolume;     totLim = TotalVolumeLimit;     tpPips = TpPips;
   }
   else if(g_btcOn && trans.symbol == BTC_Symbol)
   {
      thrVol = BTC_ThresholdVolume; totLim = BTC_TotalVolumeLimit; tpPips = BTC_TpPips;
   }
   else return;

   // Lấy thông tin deal vừa được add
   ulong dealTicket = trans.deal;
   if(dealTicket == 0) return;

   // Chỉ xử lý deal loại DEAL_ENTRY_IN (mở vị thế mới hoặc thêm vào)
   if(!HistoryDealSelect(dealTicket)) return;
   ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   if(dealEntry != DEAL_ENTRY_IN) return;

   // Lọc magic number
   if(MagicNumber != 0 && HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != MagicNumber) return;

   // Lấy position ID gắn với deal này
   ulong positionID = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);

   // Tìm position ticket khớp với positionID
   // (Trong MT5, position ticket = position ID)
   ulong newTicket = 0;
   Sleep(300); // đợi position vào pool
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != trans.symbol) continue;
      if((ulong)PositionGetInteger(POSITION_IDENTIFIER) == positionID)
      {
         newTicket = t;
         break;
      }
   }

   if(newTicket == 0)
   {
      if(VerboseLog) Print("[XAU RM] Không tìm thấy position cho deal #", dealTicket);
      return;
   }

   if(!PositionSelectByTicket(newTicket)) return;

   double newVolume  = PositionGetDouble(POSITION_VOLUME);
   double currentTP  = PositionGetDouble(POSITION_TP);

   // Nếu lệnh đã có TP (set thủ công) thì không ghi đè
   if(currentTP > 0.0)
   {
      if(VerboseLog) Print("[XAU RM] #", newTicket, " đã có TP=", currentTP, " → bỏ qua");
      UpdateDashboard();
      return;
   }

   // Tính tổng volume SAU KHI lệnh mới đã vào (bao gồm lệnh này)
   double totalVolume = GetTotalVolume(trans.symbol);

   bool   needTP = false;
   string reason = "";

   // Rule 2: tổng vol > 0.4 → set TP cho lệnh mới này (bất kể volume)
   if(totalVolume > totLim + EPS)
   {
      needTP = true;
      reason = StringFormat("Rule 2: total vol %.2f > %.2f lot", totalVolume, totLim);
   }
   // Rule 1: volume lệnh này > 0.05 (0.05 vẫn OK) → set TP
   else if(newVolume > thrVol + EPS)
   {
      needTP = true;
      reason = StringFormat("Rule 1: order vol %.2f > %.2f lot", newVolume, thrVol);
   }

   if(needTP)
   {
      if(SetTakeProfit(newTicket, tpPips))
         Print("[XAU RM] ✔ TP set ", trans.symbol, " #", newTicket, " vol=", newVolume, " | ", reason);
      else
         Print("[XAU RM] ✘ TP failed #", newTicket, " Err:", GetLastError());
   }
   else
   {
      if(VerboseLog)
         Print("[XAU RM] #", newTicket, " vol=", newVolume,
               " totalVol=", totalVolume, " → không đặt TP");
   }

   UpdateDashboard();
}

//+------------------------------------------------------------------+
double GetTotalVolume(string sym)
{
   double total = 0.0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != sym) continue;
      if(MagicNumber != 0 && PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      total += PositionGetDouble(POSITION_VOLUME);
   }
   return total;
}

int GetOpenPositions(string sym)
{
   int cnt = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != sym) continue;
      if(MagicNumber != 0 && PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      cnt++;
   }
   return cnt;
}

//+------------------------------------------------------------------+
// Giá thanh lý ước tính: giá mà tại đó equity = ngưỡng stop-out.
// shortcut: giả định margin không đổi và chỉ XAU biến động (lệnh symbol khác
// đứng yên); net volume = 0 (hedge hoàn toàn) → không có giá thanh lý.
bool GetLiquidationPrice(double &liq, double &pct)
{
   double net = 0.0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != EA_Symbol) continue;
      if(MagicNumber != 0 && PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      double v = PositionGetDouble(POSITION_VOLUME);
      net += (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? v : -v;
   }

   double margin = AccountInfoDouble(ACCOUNT_MARGIN);
   double cs     = SymbolInfoDouble(EA_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   if(MathAbs(net) < EPS || margin <= 0.0 || cs <= 0.0) return false;

   double so  = AccountInfoDouble(ACCOUNT_MARGIN_SO_SO);
   double thr = (AccountInfoInteger(ACCOUNT_MARGIN_SO_MODE) == ACCOUNT_STOPOUT_MODE_PERCENT)
                ? margin * so / 100.0 : so;

   double p0 = SymbolInfoDouble(EA_Symbol, net > 0 ? SYMBOL_BID : SYMBOL_ASK);
   if(p0 <= 0.0) return false;

   liq = p0 + (thr - AccountInfoDouble(ACCOUNT_EQUITY)) / (net * cs);
   if(liq <= 0.0) return false;   // lệnh buy: giá không thể xuống dưới 0
   pct = (liq - p0) / p0 * 100.0;
   return true;
}

//+------------------------------------------------------------------+
bool SetTakeProfit(ulong ticket, double pips)
{
   if(!PositionSelectByTicket(ticket)) return false;

   string sym     = PositionGetString(POSITION_SYMBOL);
   int    digits  = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double pipSize = SymbolInfoDouble(sym, SYMBOL_POINT) * 10.0;   // 1 pip = 10 point

   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL = PositionGetDouble(POSITION_SL);
   double tp        = 0.0;

   if(posType == POSITION_TYPE_BUY)
      tp = NormalizeDouble(openPrice + pips * pipSize, digits);
   else if(posType == POSITION_TYPE_SELL)
      tp = NormalizeDouble(openPrice - pips * pipSize, digits);
   else
      return false;

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action   = TRADE_ACTION_SLTP;
   req.symbol   = sym;
   req.position = ticket;
   req.sl       = currentSL;
   req.tp       = tp;

   bool sent = OrderSend(req, res);

   if(VerboseLog)
      Print("[XAU RM] Modify #", ticket,
            " ", (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"),
            " open=", openPrice, " tp=", tp,
            " retcode=", res.retcode);

   return (sent && res.retcode == TRADE_RETCODE_DONE);
}

//+------------------------------------------------------------------+
//             D A S H B O A R D  (gọn: 2 dòng)
//+------------------------------------------------------------------+
void LabelCreate(string name, int x, int y, string text, color clr,
                 int sz, string font = "Segoe UI",
                 ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  sz);
   ObjectSetString (0, name, OBJPROP_FONT,      font);
   ObjectSetString (0, name, OBJPROP_TEXT,      text);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,    true);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,    anchor);
   ObjectSetInteger(0, name, OBJPROP_ZORDER,    10);
}

void RectCreate(string name, int x, int y, int w, int h, color bg, color border)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,      CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,   x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,   y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,       w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,       h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,     bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,       1);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,  false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,      true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER,      1);
}

void CreateDashboard()
{
   int x = PanelX, y = PanelY, W = 190, H = g_btcOn ? 106 : 64;
   int LX = x + 8, VX = x + W - 8;
   color LC = C'110,135,180';

   RectCreate(PFX+"BG", x, y, W, H, C'15,18,28', C'55,80,130');

   // Dòng 1: tên EA | tổng vol / giới hạn
   LabelCreate(PFX+"T_TITLE", LX, y+6, "XAU RM", C'120,190,255', 8, "Segoe UI Bold");
   LabelCreate(PFX+"V_TVOL",  VX, y+6, "—", C'50,215,115', 8, "Segoe UI Bold", ANCHOR_RIGHT_UPPER);

   // Dòng 2: số lệnh | cấu hình TP
   LabelCreate(PFX+"V_POS", LX, y+24, "—", LC, 8);
   LabelCreate(PFX+"V_TP",  VX, y+24,
               StringFormat("TP %.0fp · >%.2f", TpPips, ThresholdVolume),
               C'255,210,60', 8, "Segoe UI", ANCHOR_RIGHT_UPPER);

   // Dòng 3 (nhỏ): giá thanh lý ước tính
   LabelCreate(PFX+"T_LIQ", LX, y+44, "Liq. price", C'150,170,210', 8);
   LabelCreate(PFX+"V_LIQ", VX, y+44, "—", LC, 8, "Segoe UI Bold", ANCHOR_RIGHT_UPPER);

   // Dòng 4-5: BTC (chỉ khi bật)
   if(g_btcOn)
   {
      LabelCreate(PFX+"T_BTC",     LX, y+66, "BTC RM", C'120,190,255', 8, "Segoe UI Bold");
      LabelCreate(PFX+"V_BTC_VOL", VX, y+66, "—", C'50,215,115', 8, "Segoe UI Bold", ANCHOR_RIGHT_UPPER);
      LabelCreate(PFX+"V_BTC_POS", LX, y+84, "—", LC, 8);
      LabelCreate(PFX+"V_BTC_TP",  VX, y+84,
                  StringFormat("TP %.0fp · >%.2f", BTC_TpPips, BTC_ThresholdVolume),
                  C'255,210,60', 8, "Segoe UI", ANCHOR_RIGHT_UPPER);
   }

   ChartRedraw(0);
}

// Cùng điều kiện với Rule 2: chỉ đỏ khi tổng > giới hạn
color VolColor(double vol, double limit)
{
   return (vol > limit + EPS)  ? C'255,75,75' :
          (vol >= limit*0.75)  ? C'255,185,40' : C'50,215,115';
}

void UpdateDashboard()
{
   double totalVol = GetTotalVolume(EA_Symbol);
   int    openPos  = GetOpenPositions(EA_Symbol);

   ObjectSetString (0, PFX+"V_TVOL", OBJPROP_TEXT,
                    StringFormat("%.2f / %.2f lot", totalVol, TotalVolumeLimit));
   ObjectSetInteger(0, PFX+"V_TVOL", OBJPROP_COLOR, VolColor(totalVol, TotalVolumeLimit));

   if(g_btcOn)
   {
      double btcVol = GetTotalVolume(BTC_Symbol);
      ObjectSetString (0, PFX+"V_BTC_VOL", OBJPROP_TEXT,
                       StringFormat("%.2f / %.2f lot", btcVol, BTC_TotalVolumeLimit));
      ObjectSetInteger(0, PFX+"V_BTC_VOL", OBJPROP_COLOR, VolColor(btcVol, BTC_TotalVolumeLimit));
      ObjectSetString (0, PFX+"V_BTC_POS", OBJPROP_TEXT,
                       IntegerToString(GetOpenPositions(BTC_Symbol))+" orders");
   }
   ObjectSetString (0, PFX+"V_POS",  OBJPROP_TEXT,  IntegerToString(openPos)+" orders");

   double liq, pct;
   if(GetLiquidationPrice(liq, pct))
   {
      double d = MathAbs(pct);
      ObjectSetString (0, PFX+"V_LIQ", OBJPROP_TEXT,
                       StringFormat("%s (%+.1f%%)", DoubleToString(liq, 2), pct));
      ObjectSetInteger(0, PFX+"V_LIQ", OBJPROP_COLOR,
                       d < 3.0 ? C'255,75,75' : d < 8.0 ? C'255,185,40' : C'50,215,115');
   }
   else
   {
      ObjectSetString (0, PFX+"V_LIQ", OBJPROP_TEXT, "—");
      ObjectSetInteger(0, PFX+"V_LIQ", OBJPROP_COLOR, C'110,135,180');
   }
   ChartRedraw(0);
}

void DeleteDashboard()
{
   ObjectsDeleteAll(0, PFX);
   ChartRedraw(0);
}
//+------------------------------------------------------------------+
