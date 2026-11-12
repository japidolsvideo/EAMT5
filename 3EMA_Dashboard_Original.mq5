//+------------------------------------------------------------------+
//|                              XAUUSD_M5_EMA_BuySell_v4.mq5       |
//|             Buy/Sell EA - XAUUSD M5, EMA MTF Filter              |
//|                                                                  |
//|  v3.00 - Them Dashboard Debug tren chart:                        |
//|          Hien thi toan bo trang thai dieu kien BUY / SELL        |
//|          Mau xanh = PASS, Do = FAIL, Cam = SKIP/WARN             |
//|                                                                  |
//|  v3.01 - Tach gioi han pending orders va running orders rieng    |
//|                                                                  |
//|  v4.00 - Dashboard thong minh theo xu huong H1:                  |
//|          Hien thi UPTREND / DOWNTREND / SIDEWAY                  |
//|          SIDEWAY  => an het dieu kien, khong hien Buy/Sell        |
//|          UPTREND  => chi hien cac dieu kien BUY                  |
//|          DOWNTREND=> chi hien cac dieu kien SELL                 |
//+------------------------------------------------------------------+
#property copyright   "XAUUSD Buy/Sell EA"
#property version     "4.00"
#property description "Buy/Sell EA for XAUUSD M5 - EMA MTF + Smart Dashboard"

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
input ENUM_BE_MODE InpSetSLatBE   = BE_1R;
input double       InpBEOffsetPips = 11.0;

input group "--- Pending Order Expiry ---"
input int    InpPendingExpiryBars = 0;

input group "--- Close Before Weekend ---"
input ENUM_CLOSE_BEFORE_WEEKEND InpCloseBeforeWeekend = CBW_2H;
input int    InpFridayCloseHour  = 21;

input group "--- Risk Management ---"
input double InpRiskPercent       = 1.0;
input int    InpMaxPendingOrders  = 10000;    // Gioi han tong lenh PENDING (Buy Stop + Sell Stop)
input int    InpMaxRunningOrders  = 5;    // Gioi han tong lenh DANG CHAY (Positions)

input group "--- Session Filter ---"
input bool   InpUseSession     = false;
input bool   InpAllSessions    = false;
input int    InpLondonStart    = 8;
input int    InpLondonEnd      = 17;
input int    InpNYStart        = 13;
input int    InpNYEnd          = 22;

input group "--- Dashboard ---"
input bool   InpShowDashboard  = true;    // Hien thi Debug Dashboard
input int    InpDashX          = 20;      // Vi tri X (pixel tu trai)
input int    InpDashY          = 30;      // Vi tri Y (pixel tu tren)
input int    InpDashRefreshSec = 10;      // Cap nhat Dashboard moi N giay (0 = moi tick)

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
datetime g_LastDashUpdate      = 0;   // Thoi diem cap nhat Dashboard lan cuoi

// Dashboard state struct
struct DashState
{
   // --- CHUNG ---
   bool     inSession;
   bool     inWeekendClose;
   int      pendingOrders;      // So lenh pending hien tai
   int      runningOrders;      // So lenh dang chay hien tai
   bool     maxPendingOk;       // Con duoc phep dat them pending
   bool     maxRunningOk;       // Con duoc phep mo them running
   int      h1Trend;            // 1=UPTREND, -1=DOWNTREND, 0=SIDEWAY

   // --- BUY ---
   bool     buyEnabled;
   bool     buyH1PriceAboveEmaFast;
   bool     buyH1EmaFastAboveEmaSlow;
   bool     buyM5CloseAboveEma1;
   bool     buyM5Ema1AboveEma2;
   bool     buyM5Ema2AboveEma3;
   bool     buyM5LowTouchEma1;
   bool     buyEntryAboveAsk;

   double   buyH1Close;
   double   buyH1EmaFast;
   double   buyH1EmaSlow;
   double   buyM5Close;
   double   buyM5Low;
   double   buyM5Ema1;
   double   buyM5Ema2;
   double   buyM5Ema3;
   double   buyEntryPrice;
   double   buySlPrice;
   double   buyTpPrice;
   double   buyAsk;

   // --- SELL ---
   bool     sellEnabled;
   bool     sellH1PriceBelowEmaFast;
   bool     sellH1EmaFastBelowEmaSlow;
   bool     sellM5CloseBelowEma1;
   bool     sellM5Ema1BelowEma2;
   bool     sellM5Ema2BelowEma3;
   bool     sellM5HighTouchEma1;
   bool     sellEntryBelowBid;

   double   sellH1Close;
   double   sellH1EmaFast;
   double   sellH1EmaSlow;
   double   sellM5Close;
   double   sellM5High;
   double   sellM5Ema1;
   double   sellM5Ema2;
   double   sellM5Ema3;
   double   sellEntryPrice;
   double   sellSlPrice;
   double   sellTpPrice;
   double   sellBid;

   // --- RESULT ---
   string   buyBlockReason;
   string   sellBlockReason;
   bool     buySignalFired;
   bool     sellSignalFired;
};

DashState g_Dash;

//============================================================
//  DASHBOARD OBJECT NAMES (prefix)
//============================================================
#define DASH_PREFIX "DBG_"

//+------------------------------------------------------------------+
//| Forward declarations                                             |
//+------------------------------------------------------------------+
bool   IsInSession();
int    CountMagicPendingOrders();
int    CountMagicRunningOrders();
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

// Dashboard
void   DashboardDraw();
void   DashboardDelete();
void   DashLabel(string name, string text, int x, int y,
                 color clr, int fontSize = 8, string font = "Consolas");
color  StatusColor(bool ok);

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

   // Reset dash state
   ZeroMemory(g_Dash);
   g_Dash.h1Trend         = 0;
   g_Dash.buyBlockReason  = "Waiting...";
   g_Dash.sellBlockReason = "Waiting...";

   Print("===========================================");
   Print("  XAUUSD M5 Buy/Sell EA v4.00 - STARTED");
   Print("  Dashboard: ", (InpShowDashboard ? "ON" : "OFF"));
   Print("  Max Pending Orders: ", InpMaxPendingOrders);
   Print("  Max Running Orders: ", InpMaxRunningOrders);
   Print("===========================================");

   if(InpShowDashboard) DashboardDraw();

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

   DashboardDelete();
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

   // --- Kiem tra co nen tinh lai Dashboard / H1 Trend khong ---
   datetime nowTime    = TimeCurrent();
   int      refreshSec = (InpDashRefreshSec > 0) ? InpDashRefreshSec : 0;
   bool     doRefresh  = (refreshSec == 0) ||
                         ((nowTime - g_LastDashUpdate) >= (datetime)refreshSec);

   if(doRefresh)
   {
      g_LastDashUpdate = nowTime;

   // --- Update dash trang thai chung ---
   g_Dash.inWeekendClose  = inWeekendCloseWindow;
   g_Dash.inSession       = IsInSession();
   g_Dash.pendingOrders   = CountMagicPendingOrders();
   g_Dash.runningOrders   = CountMagicRunningOrders();
   g_Dash.maxPendingOk    = (g_Dash.pendingOrders < InpMaxPendingOrders);
   g_Dash.maxRunningOk    = (g_Dash.runningOrders < InpMaxRunningOrders);
   g_Dash.buyEnabled      = (InpTradeMode == TRADE_BUY_ONLY  || InpTradeMode == TRADE_BOTH);
   g_Dash.sellEnabled     = (InpTradeMode == TRADE_SELL_ONLY || InpTradeMode == TRADE_BOTH);

   // --- Tinh toan xu huong H1 ---
   {
      double _h1F[], _h1S[];
      ArraySetAsSeries(_h1F, true);
      ArraySetAsSeries(_h1S, true);
      if(CopyBuffer(hH1Fast, 0, 0, 2, _h1F) >= 2 &&
         CopyBuffer(hH1Slow, 0, 0, 2, _h1S) >= 2)
      {
         double _h1C = iClose(_Symbol, PERIOD_H1, 0);
         if     (_h1C > _h1F[0] && _h1F[0] > _h1S[0]) g_Dash.h1Trend =  1;  // UPTREND
         else if(_h1C < _h1F[0] && _h1F[0] < _h1S[0]) g_Dash.h1Trend = -1;  // DOWNTREND
         else                                            g_Dash.h1Trend =  0;  // SIDEWAY
      }
   }

      // Redraw dashboard (chi khi den luot refresh)
      if(InpShowDashboard) DashboardDraw();

   } // end if(doRefresh)

   // Chi xu ly logic vao lenh khi co nen M5 moi
   datetime barTime = iTime(_Symbol, PERIOD_M5, 0);
   bool     newBar  = (barTime != g_LastBarTime);

   if(newBar)
   {
      g_LastBarTime = barTime;

      if(InpPendingExpiryBars > 0)
         CleanExpiredPending();

      // Dieu kien cho phep dat lenh moi: phai con slot ca pending lan running
      bool canTrade = (!inWeekendCloseWindow &&
                       g_Dash.inSession      &&
                       g_Dash.maxPendingOk   &&
                       g_Dash.maxRunningOk);

      if(canTrade)
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
            g_Dash.buySignalFired  = false;
            g_Dash.sellSignalFired = false;

            if(g_Dash.buyEnabled)
               TryPlaceBuy(m5e1, m5e2, m5e3, h1Fast, h1Slow);
            if(g_Dash.sellEnabled)
               TryPlaceSell(m5e1, m5e2, m5e3, h1Fast, h1Slow);
         }
         else
         {
            g_Dash.buyBlockReason  = "Buffer read failed";
            g_Dash.sellBlockReason = "Buffer read failed";
         }
      }
      else
      {
         // Ghi ro ly do skip
         if(inWeekendCloseWindow)
         {
            g_Dash.buyBlockReason  = "Weekend close window";
            g_Dash.sellBlockReason = "Weekend close window";
         }
         else if(!g_Dash.inSession)
         {
            g_Dash.buyBlockReason  = "Outside session";
            g_Dash.sellBlockReason = "Outside session";
         }
         else if(!g_Dash.maxPendingOk)
         {
            g_Dash.buyBlockReason  = StringFormat("Max pending reached (%d/%d)", g_Dash.pendingOrders, InpMaxPendingOrders);
            g_Dash.sellBlockReason = StringFormat("Max pending reached (%d/%d)", g_Dash.pendingOrders, InpMaxPendingOrders);
         }
         else if(!g_Dash.maxRunningOk)
         {
            g_Dash.buyBlockReason  = StringFormat("Max running reached (%d/%d)", g_Dash.runningOrders, InpMaxRunningOrders);
            g_Dash.sellBlockReason = StringFormat("Max running reached (%d/%d)", g_Dash.runningOrders, InpMaxRunningOrders);
         }
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
   g_Dash.buyH1Close   = h1Close;
   g_Dash.buyH1EmaFast = h1Fast[0];
   g_Dash.buyH1EmaSlow = h1Slow[0];

   // C1: H1 Price > EMA Fast
   g_Dash.buyH1PriceAboveEmaFast = (h1Close > h1Fast[0]);
   if(!g_Dash.buyH1PriceAboveEmaFast)
   {
      g_Dash.buyBlockReason = StringFormat("H1: Price(%.2f) <= EMAFast(%.2f)", h1Close, h1Fast[0]);
      if(InpPrintLog) Print("BUY H1 FAIL: ", g_Dash.buyBlockReason);
      return;
   }

   // C2: H1 EMA Fast > EMA Slow
   g_Dash.buyH1EmaFastAboveEmaSlow = (h1Fast[0] > h1Slow[0]);
   if(!g_Dash.buyH1EmaFastAboveEmaSlow)
   {
      g_Dash.buyBlockReason = StringFormat("H1: EMAFast(%.2f) <= EMASlow(%.2f)", h1Fast[0], h1Slow[0]);
      if(InpPrintLog) Print("BUY H1 FAIL: ", g_Dash.buyBlockReason);
      return;
   }

   double sigClose = iClose(_Symbol, PERIOD_M5, 1);
   double sigLow   = iLow  (_Symbol, PERIOD_M5, 1);
   double sigEma1  = m5e1[1];

   g_Dash.buyM5Close = sigClose;
   g_Dash.buyM5Low   = sigLow;
   g_Dash.buyM5Ema1  = m5e1[1];
   g_Dash.buyM5Ema2  = m5e2[1];
   g_Dash.buyM5Ema3  = m5e3[1];

   // C3: M5 Close > EMA1
   g_Dash.buyM5CloseAboveEma1 = (sigClose > m5e1[1]);
   if(!g_Dash.buyM5CloseAboveEma1)
   {
      g_Dash.buyBlockReason = StringFormat("M5: Close(%.2f) <= EMA1(%.2f)", sigClose, m5e1[1]);
      if(InpPrintLog) Print("BUY M5 FAIL: ", g_Dash.buyBlockReason);
      return;
   }

   // C4: M5 EMA1 > EMA2
   g_Dash.buyM5Ema1AboveEma2 = (m5e1[1] > m5e2[1]);
   if(!g_Dash.buyM5Ema1AboveEma2)
   {
      g_Dash.buyBlockReason = StringFormat("M5: EMA1(%.2f) <= EMA2(%.2f)", m5e1[1], m5e2[1]);
      if(InpPrintLog) Print("BUY M5 FAIL: ", g_Dash.buyBlockReason);
      return;
   }

   // C5: M5 EMA2 > EMA3
   g_Dash.buyM5Ema2AboveEma3 = (m5e2[1] > m5e3[1]);
   if(!g_Dash.buyM5Ema2AboveEma3)
   {
      g_Dash.buyBlockReason = StringFormat("M5: EMA2(%.2f) <= EMA3(%.2f)", m5e2[1], m5e3[1]);
      if(InpPrintLog) Print("BUY M5 FAIL: ", g_Dash.buyBlockReason);
      return;
   }

   // C6: Low nen tin hieu cham EMA1
   g_Dash.buyM5LowTouchEma1 = (sigLow <= sigEma1);
   if(!g_Dash.buyM5LowTouchEma1)
   {
      g_Dash.buyBlockReason = StringFormat("M5: Low(%.2f) did not touch EMA1(%.2f)", sigLow, sigEma1);
      if(InpPrintLog) Print("BUY M5 FAIL: ", g_Dash.buyBlockReason);
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

   g_Dash.buyEntryPrice = entryPrice;
   g_Dash.buySlPrice    = slPrice;
   g_Dash.buyTpPrice    = tpPrice;
   g_Dash.buyAsk        = askNow;

   // C7: Entry > Ask
   g_Dash.buyEntryAboveAsk = (entryPrice > askNow);
   if(!g_Dash.buyEntryAboveAsk)
   {
      g_Dash.buyBlockReason = StringFormat("Entry(%.2f) <= Ask(%.2f) - invalid stop", entryPrice, askNow);
      Print("BUY WARN: ", g_Dash.buyBlockReason);
      return;
   }

   if(riskDist <= 0)
   {
      g_Dash.buyBlockReason = "riskDist <= 0";
      return;
   }

   // ALL PASS
   g_Dash.buyBlockReason = "-- ALL CONDITIONS PASSED --";

   double lots = CalculateLots(entryPrice, slPrice);
   if(lots <= 0.0)
   {
      g_Dash.buyBlockReason = "Lot calculation failed";
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
   {
      g_Dash.buySignalFired = true;
      g_Dash.buyBlockReason = StringFormat("PLACED! Entry=%.2f SL=%.2f TP=%.2f", entryPrice, slPrice, tpPrice);
      Print(">>> BUY STOP PLACED: Entry=", entryPrice, " SL=", slPrice, " TP=", tpPrice, " Lots=", lots);
   }
   else
   {
      g_Dash.buyBlockReason = StringFormat("Order failed: %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
      Print("BUY ERR: ", g_Dash.buyBlockReason);
   }
}

//+------------------------------------------------------------------+
//| TryPlaceSell                                                      |
//+------------------------------------------------------------------+
void TryPlaceSell(const double &m5e1[], const double &m5e2[], const double &m5e3[],
                  const double &h1Fast[], const double &h1Slow[])
{
   double h1Close = iClose(_Symbol, PERIOD_H1, 0);
   g_Dash.sellH1Close   = h1Close;
   g_Dash.sellH1EmaFast = h1Fast[0];
   g_Dash.sellH1EmaSlow = h1Slow[0];

   // C1: H1 Price < EMA Fast
   g_Dash.sellH1PriceBelowEmaFast = (h1Close < h1Fast[0]);
   if(!g_Dash.sellH1PriceBelowEmaFast)
   {
      g_Dash.sellBlockReason = StringFormat("H1: Price(%.2f) >= EMAFast(%.2f)", h1Close, h1Fast[0]);
      if(InpPrintLog) Print("SELL H1 FAIL: ", g_Dash.sellBlockReason);
      return;
   }

   // C2: H1 EMA Fast < EMA Slow
   g_Dash.sellH1EmaFastBelowEmaSlow = (h1Fast[0] < h1Slow[0]);
   if(!g_Dash.sellH1EmaFastBelowEmaSlow)
   {
      g_Dash.sellBlockReason = StringFormat("H1: EMAFast(%.2f) >= EMASlow(%.2f)", h1Fast[0], h1Slow[0]);
      if(InpPrintLog) Print("SELL H1 FAIL: ", g_Dash.sellBlockReason);
      return;
   }

   double sigClose = iClose(_Symbol, PERIOD_M5, 1);
   double sigHigh  = iHigh (_Symbol, PERIOD_M5, 1);
   double sigEma1  = m5e1[1];

   g_Dash.sellM5Close = sigClose;
   g_Dash.sellM5High  = sigHigh;
   g_Dash.sellM5Ema1  = m5e1[1];
   g_Dash.sellM5Ema2  = m5e2[1];
   g_Dash.sellM5Ema3  = m5e3[1];

   // C3: M5 Close < EMA1
   g_Dash.sellM5CloseBelowEma1 = (sigClose < m5e1[1]);
   if(!g_Dash.sellM5CloseBelowEma1)
   {
      g_Dash.sellBlockReason = StringFormat("M5: Close(%.2f) >= EMA1(%.2f)", sigClose, m5e1[1]);
      if(InpPrintLog) Print("SELL M5 FAIL: ", g_Dash.sellBlockReason);
      return;
   }

   // C4: M5 EMA1 < EMA2
   g_Dash.sellM5Ema1BelowEma2 = (m5e1[1] < m5e2[1]);
   if(!g_Dash.sellM5Ema1BelowEma2)
   {
      g_Dash.sellBlockReason = StringFormat("M5: EMA1(%.2f) >= EMA2(%.2f)", m5e1[1], m5e2[1]);
      if(InpPrintLog) Print("SELL M5 FAIL: ", g_Dash.sellBlockReason);
      return;
   }

   // C5: M5 EMA2 < EMA3
   g_Dash.sellM5Ema2BelowEma3 = (m5e2[1] < m5e3[1]);
   if(!g_Dash.sellM5Ema2BelowEma3)
   {
      g_Dash.sellBlockReason = StringFormat("M5: EMA2(%.2f) >= EMA3(%.2f)", m5e2[1], m5e3[1]);
      if(InpPrintLog) Print("SELL M5 FAIL: ", g_Dash.sellBlockReason);
      return;
   }

   // C6: High nen tin hieu cham EMA1
   g_Dash.sellM5HighTouchEma1 = (sigHigh >= sigEma1);
   if(!g_Dash.sellM5HighTouchEma1)
   {
      g_Dash.sellBlockReason = StringFormat("M5: High(%.2f) did not touch EMA1(%.2f)", sigHigh, sigEma1);
      if(InpPrintLog) Print("SELL M5 FAIL: ", g_Dash.sellBlockReason);
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

   g_Dash.sellEntryPrice = entryPrice;
   g_Dash.sellSlPrice    = slPrice;
   g_Dash.sellTpPrice    = tpPrice;
   g_Dash.sellBid        = bidNow;

   // C7: Entry < Bid
   g_Dash.sellEntryBelowBid = (entryPrice < bidNow);
   if(!g_Dash.sellEntryBelowBid)
   {
      g_Dash.sellBlockReason = StringFormat("Entry(%.2f) >= Bid(%.2f) - invalid stop", entryPrice, bidNow);
      Print("SELL WARN: ", g_Dash.sellBlockReason);
      return;
   }

   if(riskDist <= 0)
   {
      g_Dash.sellBlockReason = "riskDist <= 0";
      return;
   }

   // ALL PASS
   g_Dash.sellBlockReason = "-- ALL CONDITIONS PASSED --";

   double lots = CalculateLots(entryPrice, slPrice);
   if(lots <= 0.0)
   {
      g_Dash.sellBlockReason = "Lot calculation failed";
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
   {
      g_Dash.sellSignalFired = true;
      g_Dash.sellBlockReason = StringFormat("PLACED! Entry=%.2f SL=%.2f TP=%.2f", entryPrice, slPrice, tpPrice);
      Print(">>> SELL STOP PLACED: Entry=", entryPrice, " SL=", slPrice, " TP=", tpPrice, " Lots=", lots);
   }
   else
   {
      g_Dash.sellBlockReason = StringFormat("Order failed: %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
      Print("SELL ERR: ", g_Dash.sellBlockReason);
   }
}

//+------------------------------------------------------------------+
//| DASHBOARD DRAW  -  v4: hien thi theo xu huong H1                 |
//|   UPTREND   => chi hien dieu kien BUY                            |
//|   DOWNTREND => chi hien dieu kien SELL                           |
//|   SIDEWAY   => chi hien General + banner, an het Buy/Sell        |
//+------------------------------------------------------------------+
void DashboardDraw()
{
   // Xoa tat ca label cu truoc khi ve lai (tranh label cu con luon)
   ObjectsDeleteAll(0, DASH_PREFIX);

   int x  = InpDashX;
   int y  = InpDashY;
   int lh = 15;   // line height

   color cTitle  = clrWhite;
   color cHead   = clrSkyBlue;
   color cPassed = C'0,200,80';
   color cFailed = C'230,60,60';
   color cWarn   = clrOrange;
   color cGray   = clrSilver;
   color cValue  = clrKhaki;

   // ===== TIEU DE =====
   DashLabel(DASH_PREFIX+"title", "╔══ EA DASHBOARD ════════════════════════╗", x, y, cTitle, 9, "Consolas");
   y += lh;

   // ===== TRANG THAI CHUNG =====
   DashLabel(DASH_PREFIX+"hdr_gen", "  [GENERAL]", x, y, cHead, 8);
   y += lh;

   color cSess = g_Dash.inSession ? cPassed : cFailed;
   DashLabel(DASH_PREFIX+"session",
      StringFormat("  Session     : %s  (%s)",
         g_Dash.inSession ? "IN  " : "OUT ",
         (InpAllSessions ? "24/7" : (InpUseSession ? "London+NY" : "Off"))),
      x, y, cSess, 8);
   y += lh;

   color cWknd = g_Dash.inWeekendClose ? cWarn : cPassed;
   DashLabel(DASH_PREFIX+"weekend",
      StringFormat("  WeekendClose: %s", g_Dash.inWeekendClose ? "ACTIVE - no new trades" : "Off"),
      x, y, cWknd, 8);
   y += lh;

   color cPend = g_Dash.maxPendingOk ? cPassed : cFailed;
   DashLabel(DASH_PREFIX+"pending",
      StringFormat("  Pending Ord : %d / %d  %s",
         g_Dash.pendingOrders, InpMaxPendingOrders,
         g_Dash.maxPendingOk ? "[OK]" : "[FULL]"),
      x, y, cPend, 8);
   y += lh;

   color cRun = g_Dash.maxRunningOk ? cPassed : cFailed;
   DashLabel(DASH_PREFIX+"running",
      StringFormat("  Running Ord : %d / %d  %s",
         g_Dash.runningOrders, InpMaxRunningOrders,
         g_Dash.maxRunningOk ? "[OK]" : "[FULL]"),
      x, y, cRun, 8);
   y += lh;

   DashLabel(DASH_PREFIX+"sep0", "  ────────────────────────────────────────", x, y, clrDimGray, 8);
   y += lh;

   // ===== H1 TREND BANNER =====
   string trendText;
   color  trendColor;
   if(g_Dash.h1Trend == 1)
   {
      trendText  = "  H1 TREND:  [ UPTREND   ]  => cho BUY";
      trendColor = C'0,210,90';   // xanh la
   }
   else if(g_Dash.h1Trend == -1)
   {
      trendText  = "  H1 TREND:  [ DOWNTREND ]  => cho SELL";
      trendColor = C'230,60,60';  // do
   }
   else
   {
      trendText  = "  H1 TREND:  [ SIDEWAY   ]  => khong giao dich";
      trendColor = clrOrange;     // cam
   }
   DashLabel(DASH_PREFIX+"trend", trendText, x, y, trendColor, 9, "Consolas");
   y += lh;

   DashLabel(DASH_PREFIX+"sep1", "  ────────────────────────────────────────", x, y, clrDimGray, 8);
   y += lh;

   // ===== SIDEWAY: ket thuc o day =====
   if(g_Dash.h1Trend == 0)
   {
      DashLabel(DASH_PREFIX+"sideway_msg",
         "  Dang cho xu huong H1 ro rang...",
         x, y, clrOrange, 8);
      y += lh;
      DashLabel(DASH_PREFIX+"time",
         "  Updated: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS),
         x, y, clrDarkGray, 8);
      ChartRedraw();
      return;
   }

   // ===== UPTREND: chi hien BUY =====
   if(g_Dash.h1Trend == 1)
   {
      color cMode = g_Dash.buyEnabled ? cPassed : cGray;
      DashLabel(DASH_PREFIX+"mode",
         StringFormat("  Mode BUY  : %s", g_Dash.buyEnabled ? "ENABLED" : "DISABLED"),
         x, y, cMode, 8);
      y += lh;

      // --- H1 Filter ---
      DashLabel(DASH_PREFIX+"hdr_h1", "  [H1 TREND FILTER]", x, y, cHead, 8);
      y += lh;

      DashLabel(DASH_PREFIX+"h1c",
         StringFormat("  Price > EMAFast : %s  (%.2f > %.2f)",
            g_Dash.buyH1PriceAboveEmaFast ? "PASS" : "FAIL",
            g_Dash.buyH1Close, g_Dash.buyH1EmaFast),
         x, y, StatusColor(g_Dash.buyH1PriceAboveEmaFast), 8);
      y += lh;

      DashLabel(DASH_PREFIX+"h1e",
         StringFormat("  EMAFast > EMASlow: %s  (%.2f > %.2f)",
            g_Dash.buyH1EmaFastAboveEmaSlow ? "PASS" : "FAIL",
            g_Dash.buyH1EmaFast, g_Dash.buyH1EmaSlow),
         x, y, StatusColor(g_Dash.buyH1EmaFastAboveEmaSlow), 8);
      y += lh;

      DashLabel(DASH_PREFIX+"sep2", "  ────────────────────────────────────────", x, y, clrDimGray, 8);
      y += lh;

      // --- M5 Signal ---
      DashLabel(DASH_PREFIX+"hdr_m5", "  [M5 SIGNAL CANDLE]  (bar #1 = last closed)", x, y, cHead, 8);
      y += lh;

      DashLabel(DASH_PREFIX+"m5c1",
         StringFormat("  Close > EMA1 : %s  (%.2f > %.2f)",
            g_Dash.buyM5CloseAboveEma1 ? "PASS" : "FAIL",
            g_Dash.buyM5Close, g_Dash.buyM5Ema1),
         x, y, StatusColor(g_Dash.buyM5CloseAboveEma1), 8);
      y += lh;

      DashLabel(DASH_PREFIX+"m5e12",
         StringFormat("  EMA1 > EMA2  : %s  (%.2f > %.2f)",
            g_Dash.buyM5Ema1AboveEma2 ? "PASS" : "FAIL",
            g_Dash.buyM5Ema1, g_Dash.buyM5Ema2),
         x, y, StatusColor(g_Dash.buyM5Ema1AboveEma2), 8);
      y += lh;

      DashLabel(DASH_PREFIX+"m5e23",
         StringFormat("  EMA2 > EMA3  : %s  (%.2f > %.2f)",
            g_Dash.buyM5Ema2AboveEma3 ? "PASS" : "FAIL",
            g_Dash.buyM5Ema2, g_Dash.buyM5Ema3),
         x, y, StatusColor(g_Dash.buyM5Ema2AboveEma3), 8);
      y += lh;

      DashLabel(DASH_PREFIX+"m5touch",
         StringFormat("  Low <= EMA1  : %s  (%.2f <= %.2f)",
            g_Dash.buyM5LowTouchEma1 ? "PASS" : "FAIL",
            g_Dash.buyM5Low, g_Dash.buyM5Ema1),
         x, y, StatusColor(g_Dash.buyM5LowTouchEma1), 8);
      y += lh;

      DashLabel(DASH_PREFIX+"sep3", "  ────────────────────────────────────────", x, y, clrDimGray, 8);
      y += lh;

      // --- Order Checks ---
      DashLabel(DASH_PREFIX+"hdr_ord", "  [ORDER CHECKS]", x, y, cHead, 8);
      y += lh;

      DashLabel(DASH_PREFIX+"ask",
         StringFormat("  Entry > Ask  : %s  (%.2f > %.2f)",
            g_Dash.buyEntryAboveAsk ? "PASS" : "FAIL",
            g_Dash.buyEntryPrice, g_Dash.buyAsk),
         x, y, StatusColor(g_Dash.buyEntryAboveAsk), 8);
      y += lh;

      DashLabel(DASH_PREFIX+"lvl",
         StringFormat("  Entry=%.2f  SL=%.2f  TP=%.2f",
            g_Dash.buyEntryPrice, g_Dash.buySlPrice, g_Dash.buyTpPrice),
         x, y, cValue, 8);
      y += lh;

      DashLabel(DASH_PREFIX+"sep4", "  ────────────────────────────────────────", x, y, clrDimGray, 8);
      y += lh;

      // --- Result ---
      DashLabel(DASH_PREFIX+"hdr_res", "  [RESULT]", x, y, cHead, 8);
      y += lh;

      bool allPass = (StringFind(g_Dash.buyBlockReason, "ALL CONDITIONS") >= 0 || g_Dash.buySignalFired);
      color cRes = allPass ? C'0,220,100' : cFailed;
      DashLabel(DASH_PREFIX+"reason",
         "  BUY : " + g_Dash.buyBlockReason,
         x, y, cRes, 8);
      y += lh;
   }

   // ===== DOWNTREND: chi hien SELL =====
   else if(g_Dash.h1Trend == -1)
   {
      color cMode = g_Dash.sellEnabled ? cPassed : cGray;
      DashLabel(DASH_PREFIX+"mode",
         StringFormat("  Mode SELL : %s", g_Dash.sellEnabled ? "ENABLED" : "DISABLED"),
         x, y, cMode, 8);
      y += lh;

      // --- H1 Filter ---
      DashLabel(DASH_PREFIX+"hdr_h1", "  [H1 TREND FILTER]", x, y, cHead, 8);
      y += lh;

      DashLabel(DASH_PREFIX+"h1c",
         StringFormat("  Price < EMAFast : %s  (%.2f < %.2f)",
            g_Dash.sellH1PriceBelowEmaFast ? "PASS" : "FAIL",
            g_Dash.sellH1Close, g_Dash.sellH1EmaFast),
         x, y, StatusColor(g_Dash.sellH1PriceBelowEmaFast), 8);
      y += lh;

      DashLabel(DASH_PREFIX+"h1e",
         StringFormat("  EMAFast < EMASlow: %s  (%.2f < %.2f)",
            g_Dash.sellH1EmaFastBelowEmaSlow ? "PASS" : "FAIL",
            g_Dash.sellH1EmaFast, g_Dash.sellH1EmaSlow),
         x, y, StatusColor(g_Dash.sellH1EmaFastBelowEmaSlow), 8);
      y += lh;

      DashLabel(DASH_PREFIX+"sep2", "  ────────────────────────────────────────", x, y, clrDimGray, 8);
      y += lh;

      // --- M5 Signal ---
      DashLabel(DASH_PREFIX+"hdr_m5", "  [M5 SIGNAL CANDLE]  (bar #1 = last closed)", x, y, cHead, 8);
      y += lh;

      DashLabel(DASH_PREFIX+"m5c1",
         StringFormat("  Close < EMA1 : %s  (%.2f < %.2f)",
            g_Dash.sellM5CloseBelowEma1 ? "PASS" : "FAIL",
            g_Dash.sellM5Close, g_Dash.sellM5Ema1),
         x, y, StatusColor(g_Dash.sellM5CloseBelowEma1), 8);
      y += lh;

      DashLabel(DASH_PREFIX+"m5e12",
         StringFormat("  EMA1 < EMA2  : %s  (%.2f < %.2f)",
            g_Dash.sellM5Ema1BelowEma2 ? "PASS" : "FAIL",
            g_Dash.sellM5Ema1, g_Dash.sellM5Ema2),
         x, y, StatusColor(g_Dash.sellM5Ema1BelowEma2), 8);
      y += lh;

      DashLabel(DASH_PREFIX+"m5e23",
         StringFormat("  EMA2 < EMA3  : %s  (%.2f < %.2f)",
            g_Dash.sellM5Ema2BelowEma3 ? "PASS" : "FAIL",
            g_Dash.sellM5Ema2, g_Dash.sellM5Ema3),
         x, y, StatusColor(g_Dash.sellM5Ema2BelowEma3), 8);
      y += lh;

      DashLabel(DASH_PREFIX+"m5touch",
         StringFormat("  High >= EMA1 : %s  (%.2f >= %.2f)",
            g_Dash.sellM5HighTouchEma1 ? "PASS" : "FAIL",
            g_Dash.sellM5High, g_Dash.sellM5Ema1),
         x, y, StatusColor(g_Dash.sellM5HighTouchEma1), 8);
      y += lh;

      DashLabel(DASH_PREFIX+"sep3", "  ────────────────────────────────────────", x, y, clrDimGray, 8);
      y += lh;

      // --- Order Checks ---
      DashLabel(DASH_PREFIX+"hdr_ord", "  [ORDER CHECKS]", x, y, cHead, 8);
      y += lh;

      DashLabel(DASH_PREFIX+"bid",
         StringFormat("  Entry < Bid  : %s  (%.2f < %.2f)",
            g_Dash.sellEntryBelowBid ? "PASS" : "FAIL",
            g_Dash.sellEntryPrice, g_Dash.sellBid),
         x, y, StatusColor(g_Dash.sellEntryBelowBid), 8);
      y += lh;

      DashLabel(DASH_PREFIX+"lvl",
         StringFormat("  Entry=%.2f  SL=%.2f  TP=%.2f",
            g_Dash.sellEntryPrice, g_Dash.sellSlPrice, g_Dash.sellTpPrice),
         x, y, cValue, 8);
      y += lh;

      DashLabel(DASH_PREFIX+"sep4", "  ────────────────────────────────────────", x, y, clrDimGray, 8);
      y += lh;

      // --- Result ---
      DashLabel(DASH_PREFIX+"hdr_res", "  [RESULT]", x, y, cHead, 8);
      y += lh;

      bool allPass = (StringFind(g_Dash.sellBlockReason, "ALL CONDITIONS") >= 0 || g_Dash.sellSignalFired);
      color cRes = allPass ? C'0,220,100' : cFailed;
      DashLabel(DASH_PREFIX+"reason",
         "  SELL: " + g_Dash.sellBlockReason,
         x, y, cRes, 8);
      y += lh;
   }

   // ===== TIMESTAMP =====
   DashLabel(DASH_PREFIX+"sep5", "  ────────────────────────────────────────", x, y, clrDimGray, 8);
   y += lh;
   DashLabel(DASH_PREFIX+"time",
      "  Updated: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS),
      x, y, clrDarkGray, 8);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Helper: tao / update 1 label tren chart                          |
//+------------------------------------------------------------------+
void DashLabel(string name, string text, int x, int y,
               color clr, int fontSize = 8, string font = "Consolas")
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   }
   ObjectSetString (0, name, OBJPROP_TEXT,      text);
   ObjectSetString (0, name, OBJPROP_FONT,      font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
}

//+------------------------------------------------------------------+
//| Xoa toan bo object dashboard                                      |
//+------------------------------------------------------------------+
void DashboardDelete()
{
   ObjectsDeleteAll(0, DASH_PREFIX);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| StatusColor - xanh neu pass, do neu fail                         |
//+------------------------------------------------------------------+
color StatusColor(bool ok)
{
   return(ok ? C'0,200,80' : C'230,60,60');
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
//| PipSize                                                           |
//+------------------------------------------------------------------+
double PipSize()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
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