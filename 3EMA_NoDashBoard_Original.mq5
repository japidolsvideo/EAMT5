//+------------------------------------------------------------------+
//|                              XAUUSD_M5_EMA_BuySell_v3.mq5       |
//|             Buy/Sell EA - XAUUSD M5, EMA MTF Filter              |
//|                                                                  |
//|  v3.01 - Tach gioi han pending orders va running orders rieng    |
//|  v3.02 - Bo toan bo Dashboard                                    |
//+------------------------------------------------------------------+
#property copyright   "XAUUSD Buy/Sell EA"
#property version     "3.02"
#property description "Buy/Sell EA for XAUUSD M5 - EMA MTF"

#include <Trade\Trade.mqh>

//============================================================
//  ENUM
//============================================================
enum ENUM_TRADE_MODE
{
   TRADE_BUY_ONLY  = 0,   // Chi Buy
   TRADE_SELL_ONLY = 1,   // Chi Sell
   TRADE_BOTH      = 2    // Ca Buy va Sell
};

enum ENUM_BE_MODE
{
   BE_NO = 0,   // No (SL co dinh, khong doi)
   BE_1R = 1,   // 1R (chay duoc 1R thi doi SL ve BE)
   BE_2R = 2,   // 2R (chay duoc 2R thi doi SL ve BE)
   BE_3R = 3    // 3R (chay duoc 3R thi doi SL ve BE)
};

enum ENUM_CLOSE_BEFORE_WEEKEND
{
   CBW_NO  = 0,   // No (giu lenh qua tuan)
   CBW_1H  = 1,   // Close all 1h before Friday close
   CBW_2H  = 2,   // Close all 2h before Friday close
   CBW_3H  = 3    // Close all 3h before Friday close
};

//============================================================
//  INPUT PARAMETERS
//============================================================

input group "--- Trade Direction Mode ---"
input ENUM_TRADE_MODE InpTradeMode = TRADE_BOTH;

input group "--- H1 Trend Filter ---"
input int    InpH1_EMA_Fast    = 8;
input int    InpH1_EMA_Slow    = 21;

input group "--- M5 EMA Settings ---"
input int    InpM5_EMA1        = 8;
input int    InpM5_EMA2        = 13;
input int    InpM5_EMA3        = 21;

input group "--- Entry / Exit Rules ---"
input int    InpLookbackBars   = 5;
input double InpEntryPips      = 5.0;
input double InpSLPips         = 5.0;
input double InpRR             = 3.0;

input group "--- Break-Even Stop Loss ---"
input ENUM_BE_MODE InpSetSLatBE    = BE_1R;
input double       InpBEOffsetPips = 11.0;

input group "--- Pending Order Expiry ---"
input int    InpPendingExpiryBars = 0;

input group "--- Close Before Weekend ---"
input ENUM_CLOSE_BEFORE_WEEKEND InpCloseBeforeWeekend = CBW_2H;
input int    InpFridayCloseHour  = 21;

input group "--- Risk Management ---"
input double InpRiskPercent      = 1.0;
input int    InpMaxPendingOrders = 10000;    // Gioi han tong lenh PENDING (Buy Stop + Sell Stop)
input int    InpMaxRunningOrders = 5;    // Gioi han tong lenh DANG CHAY (Positions)

input group "--- Session Filter ---"
input bool   InpUseSession     = false;
input bool   InpAllSessions    = false;
input int    InpLondonStart    = 8;
input int    InpLondonEnd      = 17;
input int    InpNYStart        = 13;
input int    InpNYEnd          = 22;

input group "--- General ---"
input ulong  InpMagic          = 20250001;
input bool   InpPrintLog       = true;

//============================================================
//  GLOBAL VARIABLES
//============================================================
CTrade   trade;

int      hH1Fast  = INVALID_HANDLE;
int      hH1Slow  = INVALID_HANDLE;
int      hM5E1    = INVALID_HANDLE;
int      hM5E2    = INVALID_HANDLE;
int      hM5E3    = INVALID_HANDLE;

datetime g_LastBarTime         = 0;
datetime g_LastWeekendCloseLog = 0;

//+------------------------------------------------------------------+
//| Forward declarations                                             |
//+------------------------------------------------------------------+
bool   IsInSession();
int    CountMagicPendingOrders();
int    CountMagicRunningOrders();
bool   HasActiveBuyStop();
bool   HasActiveSellStop();
double PipSize();
double CalculateLots(double entryPrice, double slPrice);
void   TryPlaceBuy(const double &m5e1[], const double &m5e2[], const double &m5e3[],
                   const double &h1Fast[], const double &h1Slow[]);
void   TryPlaceSell(const double &m5e1[], const double &m5e2[], const double &m5e3[],
                    const double &h1Fast[], const double &h1Slow[]);
void   ManageBreakEven();
void   CleanExpiredPending();
bool   IsWeekendCloseWindow();
void   CloseAllBeforeWeekend();

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   if(StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0)
      Print("WARNING: EA designed for XAUUSD - current symbol: ", _Symbol);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(30);

   hH1Fast = iMA(_Symbol, PERIOD_H1, InpH1_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   hH1Slow = iMA(_Symbol, PERIOD_H1, InpH1_EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   hM5E1   = iMA(_Symbol, PERIOD_M5, InpM5_EMA1,     0, MODE_EMA, PRICE_CLOSE);
   hM5E2   = iMA(_Symbol, PERIOD_M5, InpM5_EMA2,     0, MODE_EMA, PRICE_CLOSE);
   hM5E3   = iMA(_Symbol, PERIOD_M5, InpM5_EMA3,     0, MODE_EMA, PRICE_CLOSE);

   if(hH1Fast == INVALID_HANDLE || hH1Slow == INVALID_HANDLE ||
      hM5E1   == INVALID_HANDLE || hM5E2   == INVALID_HANDLE ||
      hM5E3   == INVALID_HANDLE)
   {
      Alert("ERROR: Cannot create indicator handles!");
      return(INIT_FAILED);
   }

   if(InpFridayCloseHour < 0 || InpFridayCloseHour > 23)
   {
      Alert("ERROR: InpFridayCloseHour must be in 0..23");
      return(INIT_FAILED);
   }

   Print("===========================================");
   Print("  XAUUSD M5 Buy/Sell EA v3.02 - STARTED");
   Print("  Max Pending Orders: ", InpMaxPendingOrders);
   Print("  Max Running Orders: ", InpMaxRunningOrders);
   Print("===========================================");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(hH1Fast != INVALID_HANDLE) IndicatorRelease(hH1Fast);
   if(hH1Slow != INVALID_HANDLE) IndicatorRelease(hH1Slow);
   if(hM5E1   != INVALID_HANDLE) IndicatorRelease(hM5E1);
   if(hM5E2   != INVALID_HANDLE) IndicatorRelease(hM5E2);
   if(hM5E3   != INVALID_HANDLE) IndicatorRelease(hM5E3);
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   bool inWeekendCloseWindow = false;
   if(InpCloseBeforeWeekend != CBW_NO)
   {
      inWeekendCloseWindow = IsWeekendCloseWindow();
      if(inWeekendCloseWindow)
         CloseAllBeforeWeekend();
   }

   if(InpSetSLatBE != BE_NO)
      ManageBreakEven();

   // Chi xu ly logic vao lenh khi co nen M5 moi
   datetime barTime = iTime(_Symbol, PERIOD_M5, 0);
   bool     newBar  = (barTime != g_LastBarTime);

   if(newBar)
   {
      g_LastBarTime = barTime;

      if(InpPendingExpiryBars > 0)
         CleanExpiredPending();

      bool inSession      = IsInSession();
      bool maxPendingOk   = (CountMagicPendingOrders() < InpMaxPendingOrders);
      bool maxRunningOk   = (CountMagicRunningOrders() < InpMaxRunningOrders);
      bool buyEnabled     = (InpTradeMode == TRADE_BUY_ONLY  || InpTradeMode == TRADE_BOTH);
      bool sellEnabled    = (InpTradeMode == TRADE_SELL_ONLY || InpTradeMode == TRADE_BOTH);

      if(!inWeekendCloseWindow && inSession && maxPendingOk && maxRunningOk)
      {
         int barsNeeded = InpLookbackBars + 4;
         if(barsNeeded < 3) barsNeeded = 3;

         double h1Fast[], h1Slow[];
         double m5e1[], m5e2[], m5e3[];

         ArraySetAsSeries(h1Fast, true); ArraySetAsSeries(h1Slow, true);
         ArraySetAsSeries(m5e1,   true); ArraySetAsSeries(m5e2,   true);
         ArraySetAsSeries(m5e3,   true);

         bool bufOk = true;
         if(CopyBuffer(hH1Fast, 0, 0, 3, h1Fast) < 3) bufOk = false;
         if(CopyBuffer(hH1Slow, 0, 0, 3, h1Slow) < 3) bufOk = false;
         if(CopyBuffer(hM5E1, 0, 0, barsNeeded, m5e1) < barsNeeded) bufOk = false;
         if(CopyBuffer(hM5E2, 0, 0, barsNeeded, m5e2) < barsNeeded) bufOk = false;
         if(CopyBuffer(hM5E3, 0, 0, barsNeeded, m5e3) < barsNeeded) bufOk = false;

         if(bufOk)
         {
            if(buyEnabled)  TryPlaceBuy (m5e1, m5e2, m5e3, h1Fast, h1Slow);
            if(sellEnabled) TryPlaceSell(m5e1, m5e2, m5e3, h1Fast, h1Slow);
         }
         else
            Print("WARN: Buffer read failed - skip this bar");
      }
      else
      {
         if(inWeekendCloseWindow)
            Print("SKIP: Weekend close window");
         else if(!inSession)
            Print("SKIP: Outside session");
         else if(!maxPendingOk)
            Print("SKIP: Max pending reached (", CountMagicPendingOrders(), "/", InpMaxPendingOrders, ")");
         else if(!maxRunningOk)
            Print("SKIP: Max running reached (", CountMagicRunningOrders(), "/", InpMaxRunningOrders, ")");
      }
   }
}

//+------------------------------------------------------------------+
//| TryPlaceBuy                                                       |
//+------------------------------------------------------------------+
void TryPlaceBuy(const double &m5e1[], const double &m5e2[], const double &m5e3[],
                 const double &h1Fast[], const double &h1Slow[])
{
   double h1Close = iClose(_Symbol, PERIOD_H1, 0);

   // C1: H1 Price > EMA Fast
   if(h1Close <= h1Fast[0])
   {
      if(InpPrintLog) Print("BUY FAIL: H1 Price(", h1Close, ") <= EMAFast(", h1Fast[0], ")");
      return;
   }

   // C2: H1 EMA Fast > EMA Slow
   if(h1Fast[0] <= h1Slow[0])
   {
      if(InpPrintLog) Print("BUY FAIL: H1 EMAFast(", h1Fast[0], ") <= EMASlow(", h1Slow[0], ")");
      return;
   }

   double sigClose = iClose(_Symbol, PERIOD_M5, 1);
   double sigLow   = iLow  (_Symbol, PERIOD_M5, 1);
   double sigEma1  = m5e1[1];

   // C3: M5 Close > EMA1
   if(sigClose <= m5e1[1])
   {
      if(InpPrintLog) Print("BUY FAIL: M5 Close(", sigClose, ") <= EMA1(", m5e1[1], ")");
      return;
   }

   // C4: M5 EMA1 > EMA2
   if(m5e1[1] <= m5e2[1])
   {
      if(InpPrintLog) Print("BUY FAIL: M5 EMA1(", m5e1[1], ") <= EMA2(", m5e2[1], ")");
      return;
   }

   // C5: M5 EMA2 > EMA3
   if(m5e2[1] <= m5e3[1])
   {
      if(InpPrintLog) Print("BUY FAIL: M5 EMA2(", m5e2[1], ") <= EMA3(", m5e3[1], ")");
      return;
   }

   // C6: Low nen tin hieu cham EMA1
   if(sigLow > sigEma1)
   {
      if(InpPrintLog) Print("BUY FAIL: M5 Low(", sigLow, ") did not touch EMA1(", sigEma1, ")");
      return;
   }

   // Tinh Entry / SL / TP
   double highestHigh = 0.0;
   for(int i = 2; i <= 1 + InpLookbackBars; i++)
   {
      double h = iHigh(_Symbol, PERIOD_M5, i);
      if(h > highestHigh) highestHigh = h;
   }

   double pip        = PipSize();
   double entryPrice = NormalizeDouble(highestHigh + InpEntryPips * pip, _Digits);
   double slPrice    = NormalizeDouble(sigLow - InpSLPips * pip, _Digits);
   double riskDist   = entryPrice - slPrice;
   double tpPrice    = NormalizeDouble(entryPrice + InpRR * riskDist, _Digits);
   double askNow     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // C7: Entry > Ask
   if(entryPrice <= askNow)
   {
      Print("BUY WARN: Entry(", entryPrice, ") <= Ask(", askNow, ") - invalid stop");
      return;
   }

   if(riskDist <= 0)
   {
      Print("BUY WARN: riskDist <= 0");
      return;
   }

   // C8: Chua co Buy Stop pending
   if(HasActiveBuyStop())
   {
      if(InpPrintLog) Print("BUY INFO: Buy Stop already pending - skip");
      return;
   }

   double lots = CalculateLots(entryPrice, slPrice);
   if(lots <= 0.0)
   {
      Print("BUY ERR: Lot size calculation failed");
      return;
   }

   bool ok = trade.BuyStop(lots,
                           entryPrice,
                           _Symbol,
                           slPrice,
                           tpPrice,
                           ORDER_TIME_GTC,
                           (datetime)0,
                           "XAU-M5-EMA-BUY");
   if(ok)
      Print(">>> BUY STOP PLACED: Entry=", entryPrice, " SL=", slPrice, " TP=", tpPrice, " Lots=", lots);
   else
      Print("BUY ERR: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| TryPlaceSell                                                      |
//+------------------------------------------------------------------+
void TryPlaceSell(const double &m5e1[], const double &m5e2[], const double &m5e3[],
                  const double &h1Fast[], const double &h1Slow[])
{
   double h1Close = iClose(_Symbol, PERIOD_H1, 0);

   // C1: H1 Price < EMA Fast
   if(h1Close >= h1Fast[0])
   {
      if(InpPrintLog) Print("SELL FAIL: H1 Price(", h1Close, ") >= EMAFast(", h1Fast[0], ")");
      return;
   }

   // C2: H1 EMA Fast < EMA Slow
   if(h1Fast[0] >= h1Slow[0])
   {
      if(InpPrintLog) Print("SELL FAIL: H1 EMAFast(", h1Fast[0], ") >= EMASlow(", h1Slow[0], ")");
      return;
   }

   double sigClose = iClose(_Symbol, PERIOD_M5, 1);
   double sigHigh  = iHigh (_Symbol, PERIOD_M5, 1);
   double sigEma1  = m5e1[1];

   // C3: M5 Close < EMA1
   if(sigClose >= m5e1[1])
   {
      if(InpPrintLog) Print("SELL FAIL: M5 Close(", sigClose, ") >= EMA1(", m5e1[1], ")");
      return;
   }

   // C4: M5 EMA1 < EMA2
   if(m5e1[1] >= m5e2[1])
   {
      if(InpPrintLog) Print("SELL FAIL: M5 EMA1(", m5e1[1], ") >= EMA2(", m5e2[1], ")");
      return;
   }

   // C5: M5 EMA2 < EMA3
   if(m5e2[1] >= m5e3[1])
   {
      if(InpPrintLog) Print("SELL FAIL: M5 EMA2(", m5e2[1], ") >= EMA3(", m5e3[1], ")");
      return;
   }

   // C6: High nen tin hieu cham EMA1
   if(sigHigh < sigEma1)
   {
      if(InpPrintLog) Print("SELL FAIL: M5 High(", sigHigh, ") did not touch EMA1(", sigEma1, ")");
      return;
   }

   double lowestLow = DBL_MAX;
   for(int i = 2; i <= 1 + InpLookbackBars; i++)
   {
      double l = iLow(_Symbol, PERIOD_M5, i);
      if(l < lowestLow) lowestLow = l;
   }

   double pip        = PipSize();
   double entryPrice = NormalizeDouble(lowestLow - InpEntryPips * pip, _Digits);
   double slPrice    = NormalizeDouble(sigHigh + InpSLPips * pip, _Digits);
   double riskDist   = slPrice - entryPrice;
   double tpPrice    = NormalizeDouble(entryPrice - InpRR * riskDist, _Digits);
   double bidNow     = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // C7: Entry < Bid
   if(entryPrice >= bidNow)
   {
      Print("SELL WARN: Entry(", entryPrice, ") >= Bid(", bidNow, ") - invalid stop");
      return;
   }

   if(riskDist <= 0)
   {
      Print("SELL WARN: riskDist <= 0");
      return;
   }

   // C8: Chua co Sell Stop pending
   if(HasActiveSellStop())
   {
      if(InpPrintLog) Print("SELL INFO: Sell Stop already pending - skip");
      return;
   }

   double lots = CalculateLots(entryPrice, slPrice);
   if(lots <= 0.0)
   {
      Print("SELL ERR: Lot size calculation failed");
      return;
   }

   bool ok = trade.SellStop(lots,
                            entryPrice,
                            _Symbol,
                            slPrice,
                            tpPrice,
                            ORDER_TIME_GTC,
                            (datetime)0,
                            "XAU-M5-EMA-SELL");
   if(ok)
      Print(">>> SELL STOP PLACED: Entry=", entryPrice, " SL=", slPrice, " TP=", tpPrice, " Lots=", lots);
   else
      Print("SELL ERR: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| ManageBreakEven                                                   |
//+------------------------------------------------------------------+
void ManageBreakEven()
{
   if(InpSetSLatBE == BE_NO) return;

   double rMultiplier = 1.0;
   if(InpSetSLatBE == BE_2R) rMultiplier = 2.0;
   if(InpSetSLatBE == BE_3R) rMultiplier = 3.0;

   double pip    = PipSize();
   double offset = InpBEOffsetPips * pip;

   long   stopLevelPts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minStop      = stopLevelPts * _Point;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tkt = PositionGetTicket(i);
      if(tkt == 0) continue;
      if(!PositionSelectByTicket(tkt)) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL)        != _Symbol)  continue;

      long   posType = PositionGetInteger(POSITION_TYPE);
      double entry   = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL   = PositionGetDouble(POSITION_SL);
      double curTP   = PositionGetDouble(POSITION_TP);

      if(posType == POSITION_TYPE_BUY)
      {
         double newSL = NormalizeDouble(entry + offset, _Digits);
         if(curSL > 0 && curSL >= newSL - _Point*0.5) continue;
         double rInit = entry - curSL;
         if(curSL <= 0 || rInit <= 0) continue;
         double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double profit = bid - entry;
         if(profit < rMultiplier * rInit) continue;
         if(minStop > 0 && (bid - newSL) < minStop) continue;
         if(trade.PositionModify(tkt, newSL, curTP))
            Print(">>> BE MOVED [BUY #", tkt, "] SL: ", curSL, " -> ", newSL);
         else
            Print("BE ERR BUY #", tkt, " code=", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         double newSL = NormalizeDouble(entry - offset, _Digits);
         if(curSL > 0 && curSL <= newSL + _Point*0.5) continue;
         double rInit = curSL - entry;
         if(curSL <= 0 || rInit <= 0) continue;
         double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double profit = entry - ask;
         if(profit < rMultiplier * rInit) continue;
         if(minStop > 0 && (newSL - ask) < minStop) continue;
         if(trade.PositionModify(tkt, newSL, curTP))
            Print(">>> BE MOVED [SELL #", tkt, "] SL: ", curSL, " -> ", newSL);
         else
            Print("BE ERR SELL #", tkt, " code=", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
      }
   }
}

//+------------------------------------------------------------------+
//| CleanExpiredPending                                               |
//+------------------------------------------------------------------+
void CleanExpiredPending()
{
   if(InpPendingExpiryBars <= 0) return;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong tkt = OrderGetTicket(i);
      if(tkt == 0) continue;
      if(!OrderSelect(tkt)) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;
      if(OrderGetString(ORDER_SYMBOL)        != _Symbol)  continue;

      long type = OrderGetInteger(ORDER_TYPE);
      if(type != (long)ORDER_TYPE_BUY_STOP &&
         type != (long)ORDER_TYPE_SELL_STOP) continue;

      datetime setupTime = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
      if(setupTime <= 0) continue;

      int bars = iBarShift(_Symbol, PERIOD_M5, setupTime, false);
      if(bars < 0) continue;

      if(bars >= InpPendingExpiryBars)
      {
         string typeStr = (type == (long)ORDER_TYPE_BUY_STOP) ? "BUY STOP" : "SELL STOP";
         if(trade.OrderDelete(tkt))
            Print(">>> EXPIRED: ", typeStr, " #", tkt, " after ", bars, " M5 bars");
         else
            Print("EXPIRY ERR #", tkt, " code=", trade.ResultRetcode());
      }
   }
}

//+------------------------------------------------------------------+
//| IsWeekendCloseWindow                                              |
//+------------------------------------------------------------------+
bool IsWeekendCloseWindow()
{
   if(InpCloseBeforeWeekend == CBW_NO) return(false);

   int hoursBefore = 0;
   if(InpCloseBeforeWeekend == CBW_1H) hoursBefore = 1;
   if(InpCloseBeforeWeekend == CBW_2H) hoursBefore = 2;
   if(InpCloseBeforeWeekend == CBW_3H) hoursBefore = 3;

   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   if(t.day_of_week != 5) return(false);

   int nowMinutes   = t.hour * 60 + t.min;
   int closeMinutes = InpFridayCloseHour * 60;
   int startMinutes = closeMinutes - hoursBefore * 60;
   if(startMinutes < 0) startMinutes = 0;

   return(nowMinutes >= startMinutes && nowMinutes < closeMinutes);
}

//+------------------------------------------------------------------+
//| CloseAllBeforeWeekend                                             |
//+------------------------------------------------------------------+
void CloseAllBeforeWeekend()
{
   datetime nowT = TimeCurrent();
   bool doLog = (nowT - g_LastWeekendCloseLog) >= 60;
   int closedPos = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tkt = PositionGetTicket(i);
      if(tkt == 0) continue;
      if(!PositionSelectByTicket(tkt)) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL)        != _Symbol)  continue;

      if(trade.PositionClose(tkt))
      {
         closedPos++;
         Print(">>> WEEKEND CLOSE: Position #", tkt, " closed");
      }
      else
         Print("WEEKEND CLOSE ERR: Position #", tkt, " code=", trade.ResultRetcode());
   }

   if(doLog && closedPos > 0)
   {
      Print("=== WEEKEND CLOSE: closed ", closedPos, " position(s). Pending kept. ===");
      g_LastWeekendCloseLog = nowT;
   }
}

//+------------------------------------------------------------------+
//| IsInSession                                                       |
//+------------------------------------------------------------------+
bool IsInSession()
{
   if(!InpUseSession || InpAllSessions) return(true);
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   int h = t.hour;
   bool inLondon = (h >= InpLondonStart && h < InpLondonEnd);
   bool inNY     = (h >= InpNYStart     && h < InpNYEnd);
   return(inLondon || inNY);
}

//+------------------------------------------------------------------+
//| CountMagicPendingOrders - Dem lenh pending (Buy Stop, Sell Stop) |
//+------------------------------------------------------------------+
int CountMagicPendingOrders()
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong tkt = OrderGetTicket(i);
      if(tkt == 0) continue;
      if(OrderSelect(tkt))
         if((ulong)OrderGetInteger(ORDER_MAGIC) == InpMagic &&
            OrderGetString(ORDER_SYMBOL) == _Symbol)
            count++;
   }
   return(count);
}

//+------------------------------------------------------------------+
//| CountMagicRunningOrders - Dem lenh dang chay (Positions)         |
//+------------------------------------------------------------------+
int CountMagicRunningOrders()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tkt = PositionGetTicket(i);
      if(tkt == 0) continue;
      if(PositionSelectByTicket(tkt))
         if((ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
            count++;
   }
   return(count);
}

//+------------------------------------------------------------------+
//| HasActiveBuyStop                                                   |
//+------------------------------------------------------------------+
bool HasActiveBuyStop()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong tkt = OrderGetTicket(i);
      if(tkt == 0) continue;
      if(OrderSelect(tkt))
         if((ulong)OrderGetInteger(ORDER_MAGIC) == InpMagic &&
            OrderGetString(ORDER_SYMBOL) == _Symbol &&
            OrderGetInteger(ORDER_TYPE) == (long)ORDER_TYPE_BUY_STOP)
            return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| HasActiveSellStop                                                  |
//+------------------------------------------------------------------+
bool HasActiveSellStop()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong tkt = OrderGetTicket(i);
      if(tkt == 0) continue;
      if(OrderSelect(tkt))
         if((ulong)OrderGetInteger(ORDER_MAGIC) == InpMagic &&
            OrderGetString(ORDER_SYMBOL) == _Symbol &&
            OrderGetInteger(ORDER_TYPE) == (long)ORDER_TYPE_SELL_STOP)
            return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| PipSize                                                           |
//+------------------------------------------------------------------+
double PipSize()
{
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(digits == 3 || digits == 5)
      return(point * 10.0);
   return(point * 10.0);
}

//+------------------------------------------------------------------+
//| CalculateLots                                                     |
//+------------------------------------------------------------------+
double CalculateLots(double entryPrice, double slPrice)
{
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney  = balance * InpRiskPercent / 100.0;

   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double pt      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(tickSz <= 0.0 || pt <= 0.0 || tickVal <= 0.0)
   { Print("ERR: Cannot get symbol tick info"); return(0.0); }

   double valPerPt   = tickVal * (pt / tickSz);
   double slPoints   = MathAbs(entryPrice - slPrice) / pt;
   double lossPerLot = slPoints * valPerPt;

   if(lossPerLot <= 0.0)
   { Print("ERR: lossPerLot = 0"); return(0.0); }

   double lots    = riskMoney / lossPerLot;
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(lotStep <= 0.0) lotStep = 0.01;
   if(minLot  <= 0.0) minLot  = 0.01;
   if(maxLot  <= 0.0) maxLot  = 100.0;

   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));

   if(InpPrintLog)
      Print("LOT: Balance=", balance, " Risk=", riskMoney,
            " SlPts=", slPoints, " LossPerLot=", lossPerLot, " => Lots=", lots);

   return(NormalizeDouble(lots, 2));
}
//+------------------------------------------------------------------+