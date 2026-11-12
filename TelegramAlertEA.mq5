//+------------------------------------------------------------------+
//|                                            TelegramAlertEA.mq5   |
//|                                          CJ TradeLife © 2026     |
//|                         Telegram Alert for Trade Events           |
//+------------------------------------------------------------------+
#property copyright "CJ TradeLife"
#property version   "1.10"
#property description "Sends Telegram alerts on Open, Close, TP Hit, SL Modified"

//--- Input parameters
input string   InpBotToken   = "";           // Bot API Token
input string   InpChatID     = "";           // Telegram Chat ID
input bool     InpAlertOpen  = true;         // Alert on Order Open
input bool     InpAlertClose = true;         // Alert on Order Close
input bool     InpAlertTP    = true;         // Alert on Take Profit Hit
input bool     InpAlertSL    = true;         // Alert on Stop Loss Modified
input bool     InpDebugMode  = true;         // Debug Mode (verbose logging)

//--- Global variables
int            g_prevPositionCount = 0;

//--- Struct to track position SL
struct PositionSLInfo
  {
   ulong          ticket;
   double         sl;
  };

PositionSLInfo g_slTracker[];

//--- Track processed deals to avoid duplicates
ulong g_lastProcessedDeal = 0;

//+------------------------------------------------------------------+
//| Debug print helper                                                 |
//+------------------------------------------------------------------+
void DebugPrint(string msg)
  {
   if(InpDebugMode)
      Print("[DEBUG] ", msg);
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("=== TelegramAlertEA v1.10 STARTING ===");
   Print("Bot Token length: ", StringLen(InpBotToken));
   Print("Chat ID: [", InpChatID, "] length: ", StringLen(InpChatID));
   Print("Alert Open: ", InpAlertOpen, " | Close: ", InpAlertClose, " | TP: ", InpAlertTP, " | SL: ", InpAlertSL);

   if(InpBotToken == "" || InpChatID == "")
     {
      Alert("TelegramAlertEA: Please configure Bot Token and Chat ID!");
      return(INIT_PARAMETERS_INCORRECT);
     }

   // Initialize position count and SL tracker
   g_prevPositionCount = PositionsTotal();
   InitSLTracker();
   Print("Initial positions count: ", g_prevPositionCount);
   Print("SL tracker size: ", ArraySize(g_slTracker));

   // Initialize deal tracking from history
   HistorySelect(0, TimeCurrent());
   int totalDeals = HistoryDealsTotal();
   if(totalDeals > 0)
     {
      g_lastProcessedDeal = HistoryDealGetTicket(totalDeals - 1);
      Print("Last deal ticket in history: ", g_lastProcessedDeal);
     }

   // Test Telegram connection
   Print("--- TESTING TELEGRAM CONNECTION ---");
   bool ok = SendTelegramMessage("✅ <b>TelegramAlertEA Started</b>\n"
                                  "📊 Account: " + (string)AccountInfoInteger(ACCOUNT_LOGIN) + "\n"
                                  "💰 Balance: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + " " + AccountInfoString(ACCOUNT_CURRENCY));
   if(ok)
      Print(">>> STARTUP MESSAGE SENT OK <<<");
   else
      Print(">>> STARTUP MESSAGE FAILED - CHECK ERRORS ABOVE <<<");

   // Set timer to check every second
   EventSetTimer(1);

   Print("=== TelegramAlertEA INIT COMPLETE ===");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   Print("TelegramAlertEA stopped. Reason: ", reason);
  }

//+------------------------------------------------------------------+
//| Timer function - main monitoring loop                              |
//+------------------------------------------------------------------+
void OnTimer()
  {
   CheckNewPositions();
   CheckClosedPositions();
   CheckSLChanges();
  }

//+------------------------------------------------------------------+
//| Also check on every tick                                           |
//+------------------------------------------------------------------+
void OnTick()
  {
   CheckNewPositions();
   CheckClosedPositions();
   CheckSLChanges();
  }

//+------------------------------------------------------------------+
//| OnTradeTransaction - most reliable way to detect trade events      |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   DebugPrint("OnTradeTransaction fired! type=" + EnumToString(trans.type) +
              " symbol=" + trans.symbol +
              " deal=" + (string)trans.deal +
              " order=" + (string)trans.order);

   // DEAL_ADD = a deal was added to history (position opened or closed)
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
     {
      DebugPrint("DEAL_ADD detected. deal_ticket=" + (string)trans.deal);

      // Give time for deal to be fully registered
      Sleep(100);

      // Select deal from history
      if(!HistoryDealSelect(trans.deal))
        {
         DebugPrint("HistoryDealSelect failed for deal " + (string)trans.deal);
         // Try broader history select
         HistorySelect(TimeCurrent() - 60, TimeCurrent());
         if(!HistoryDealSelect(trans.deal))
           {
            DebugPrint("HistoryDealSelect STILL failed after HistorySelect");
            return;
           }
        }

      long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
      DebugPrint("Deal entry type: " + EnumToString((ENUM_DEAL_ENTRY)entry));

      // New position opened
      if(entry == DEAL_ENTRY_IN)
        {
         DebugPrint(">>> DEAL_ENTRY_IN - New position opened!");
         ProcessNewDeal(trans.deal);
        }
      // Position closed
      else if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
        {
         DebugPrint(">>> DEAL_ENTRY_OUT - Position closed!");
         ProcessCloseDeal(trans.deal);
        }
     }

   // Also detect SL/TP modification via ORDER events
   if(trans.type == TRADE_TRANSACTION_POSITION)
     {
      DebugPrint("POSITION modified. symbol=" + trans.symbol);
      // SL change will be caught by CheckSLChanges
     }
  }

//+------------------------------------------------------------------+
//| Process a new deal (order opened)                                  |
//+------------------------------------------------------------------+
void ProcessNewDeal(ulong dealTicket)
  {
   if(!InpAlertOpen)
     {
      DebugPrint("Alert Open is disabled, skipping");
      return;
     }

   if(dealTicket <= g_lastProcessedDeal)
     {
      DebugPrint("Deal " + (string)dealTicket + " already processed (last=" + (string)g_lastProcessedDeal + ")");
      return;
     }
   g_lastProcessedDeal = dealTicket;

   string symbol    = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
   double volume    = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
   double price     = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
   long   dealType  = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
   int    digits    = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   string typeStr   = (dealType == DEAL_TYPE_BUY) ? "BUY 🟢" : "SELL 🔴";

   // Try to get SL/TP from the position
   double sl = 0, tp = 0;
   long posID = (long)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
   if(PositionSelectByTicket((ulong)posID))
     {
      sl = PositionGetDouble(POSITION_SL);
      tp = PositionGetDouble(POSITION_TP);
     }

   string msg = "📬 <b>New Order Opened</b>\n"
                "━━━━━━━━━━━━━━━\n"
                "🎯 Type: " + typeStr + "\n"
                "📈 Symbol: " + symbol + "\n"
                "📦 Volume: " + DoubleToString(volume, 2) + " lots\n"
                "💲 Price: " + DoubleToString(price, digits) + "\n"
                "🛑 SL: " + (sl > 0 ? DoubleToString(sl, digits) : "None") + "\n"
                "🎯 TP: " + (tp > 0 ? DoubleToString(tp, digits) : "None") + "\n"
                "🔖 Ticket: #" + (string)dealTicket;

   DebugPrint("Sending OPEN alert for " + symbol);
   bool ok = SendTelegramMessage(msg);
   DebugPrint("OPEN alert send result: " + (ok ? "OK" : "FAILED"));

   // Update SL tracker
   InitSLTracker();
  }

//+------------------------------------------------------------------+
//| Process a close deal                                               |
//+------------------------------------------------------------------+
void ProcessCloseDeal(ulong dealTicket)
  {
   if(!InpAlertClose && !InpAlertTP)
     {
      DebugPrint("Alert Close and TP both disabled, skipping");
      return;
     }

   if(dealTicket <= g_lastProcessedDeal)
     {
      DebugPrint("Deal " + (string)dealTicket + " already processed");
      return;
     }
   g_lastProcessedDeal = dealTicket;

   string symbol     = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
   double volume     = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
   double price      = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
   double profit     = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
   double commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
   double swap       = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
   long   reason     = HistoryDealGetInteger(dealTicket, DEAL_REASON);
   int    digits     = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double netProfit  = profit + commission + swap;
   string profitEmoji = (netProfit >= 0) ? "💚" : "❤️";

   DebugPrint("Close deal: symbol=" + symbol + " profit=" + DoubleToString(netProfit, 2) +
              " reason=" + EnumToString((ENUM_DEAL_REASON)reason));

   // Take Profit hit
   if(reason == DEAL_REASON_TP && InpAlertTP)
     {
      string msg = "🎯 <b>Take Profit Hit!</b>\n"
                   "━━━━━━━━━━━━━━━\n"
                   "📈 Symbol: " + symbol + "\n"
                   "📦 Volume: " + DoubleToString(volume, 2) + " lots\n"
                   "💲 Close Price: " + DoubleToString(price, digits) + "\n"
                   + profitEmoji + " Profit: " + DoubleToString(netProfit, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY) + "\n"
                   "💰 Balance: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + " " + AccountInfoString(ACCOUNT_CURRENCY);

      SendTelegramMessage(msg);
      InitSLTracker();
      return;
     }

   // All other close reasons
   if(InpAlertClose)
     {
      string reasonStr = "";
      if(reason == DEAL_REASON_SL)
         reasonStr = "🛑 Stop Loss Hit!";
      else if(reason == DEAL_REASON_TP)
         reasonStr = "🎯 Take Profit Hit!";
      else if(reason == DEAL_REASON_CLIENT)
         reasonStr = "👤 Manual Close";
      else if(reason == DEAL_REASON_EXPERT)
         reasonStr = "🤖 EA Close";
      else
         reasonStr = "📋 Closed (reason=" + (string)reason + ")";

      string msg = "📕 <b>Order Closed</b>\n"
                   "━━━━━━━━━━━━━━━\n"
                   "📌 Reason: " + reasonStr + "\n"
                   "📈 Symbol: " + symbol + "\n"
                   "📦 Volume: " + DoubleToString(volume, 2) + " lots\n"
                   "💲 Close Price: " + DoubleToString(price, digits) + "\n"
                   + profitEmoji + " Profit: " + DoubleToString(netProfit, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY) + "\n"
                   "💰 Balance: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + " " + AccountInfoString(ACCOUNT_CURRENCY);

      SendTelegramMessage(msg);
     }

   InitSLTracker();
  }

//+------------------------------------------------------------------+
//| Initialize SL tracker with current positions                       |
//+------------------------------------------------------------------+
void InitSLTracker()
  {
   int total = PositionsTotal();
   ArrayResize(g_slTracker, total);

   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
        {
         g_slTracker[i].ticket = ticket;
         g_slTracker[i].sl     = PositionGetDouble(POSITION_SL);
        }
     }
  }

//+------------------------------------------------------------------+
//| Check for new positions (fallback - polling)                       |
//+------------------------------------------------------------------+
void CheckNewPositions()
  {
   int currentCount = PositionsTotal();

   if(currentCount > g_prevPositionCount && InpAlertOpen)
     {
      DebugPrint("Position count changed: " + (string)g_prevPositionCount + " -> " + (string)currentCount);

      for(int i = 0; i < currentCount; i++)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0 && !IsTicketInTracker(ticket))
           {
            DebugPrint("New position found via polling: ticket=" + (string)ticket);
            // OnTradeTransaction should handle this, but just in case
            string symbol    = PositionGetString(POSITION_SYMBOL);
            double volume    = PositionGetDouble(POSITION_VOLUME);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double sl        = PositionGetDouble(POSITION_SL);
            double tp        = PositionGetDouble(POSITION_TP);
            long   type      = PositionGetInteger(POSITION_TYPE);
            string typeStr   = (type == POSITION_TYPE_BUY) ? "BUY 🟢" : "SELL 🔴";
            int    digits    = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

            string msg = "📬 <b>New Order Opened</b>\n"
                         "━━━━━━━━━━━━━━━\n"
                         "🎯 Type: " + typeStr + "\n"
                         "📈 Symbol: " + symbol + "\n"
                         "📦 Volume: " + DoubleToString(volume, 2) + " lots\n"
                         "💲 Price: " + DoubleToString(openPrice, digits) + "\n"
                         "🛑 SL: " + (sl > 0 ? DoubleToString(sl, digits) : "None") + "\n"
                         "🎯 TP: " + (tp > 0 ? DoubleToString(tp, digits) : "None") + "\n"
                         "🔖 Ticket: #" + (string)ticket;

            DebugPrint("Sending OPEN alert via polling for " + symbol);
            SendTelegramMessage(msg);
           }
        }
     }

   g_prevPositionCount = currentCount;
   InitSLTracker();
  }

//+------------------------------------------------------------------+
//| Check for closed positions (fallback - polling via history)        |
//+------------------------------------------------------------------+
void CheckClosedPositions()
  {
   if(!InpAlertClose && !InpAlertTP)
      return;

   datetime from = TimeCurrent() - 10;
   datetime to   = TimeCurrent();

   if(!HistorySelect(from, to))
      return;

   int totalDeals = HistoryDealsTotal();

   for(int i = 0; i < totalDeals; i++)
     {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0 || dealTicket <= g_lastProcessedDeal)
         continue;

      long entry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT)
         continue;

      DebugPrint("Closed deal found via polling: " + (string)dealTicket);
      ProcessCloseDeal(dealTicket);
     }
  }

//+------------------------------------------------------------------+
//| Check for SL modifications                                         |
//+------------------------------------------------------------------+
void CheckSLChanges()
  {
   if(!InpAlertSL)
      return;

   int total = PositionsTotal();

   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      double currentSL = PositionGetDouble(POSITION_SL);
      double trackedSL = GetTrackedSL(ticket);

      if(trackedSL >= 0 && MathAbs(currentSL - trackedSL) > 0.000001)
        {
         string symbol  = PositionGetString(POSITION_SYMBOL);
         int    digits  = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
         long   type    = PositionGetInteger(POSITION_TYPE);
         string typeStr = (type == POSITION_TYPE_BUY) ? "BUY 🟢" : "SELL 🔴";

         string oldSLStr = (trackedSL > 0) ? DoubleToString(trackedSL, digits) : "None";
         string newSLStr = (currentSL > 0) ? DoubleToString(currentSL, digits) : "None";

         string moveType = "";
         if(type == POSITION_TYPE_BUY && currentSL > trackedSL)
            moveType = " (Trailing 📈)";
         else if(type == POSITION_TYPE_SELL && currentSL < trackedSL && trackedSL > 0)
            moveType = " (Trailing 📈)";

         string msg = "🔄 <b>Stop Loss Modified</b>" + moveType + "\n"
                      "━━━━━━━━━━━━━━━\n"
                      "🎯 Type: " + typeStr + "\n"
                      "📈 Symbol: " + symbol + "\n"
                      "🔖 Ticket: #" + (string)ticket + "\n"
                      "🛑 Old SL: " + oldSLStr + "\n"
                      "🛑 New SL: " + newSLStr;

         DebugPrint("SL changed for ticket " + (string)ticket + ": " + oldSLStr + " -> " + newSLStr);
         SendTelegramMessage(msg);
         UpdateTrackedSL(ticket, currentSL);
        }
     }

   if(ArraySize(g_slTracker) != total)
      InitSLTracker();
  }

//+------------------------------------------------------------------+
//| Check if ticket exists in SL tracker                               |
//+------------------------------------------------------------------+
bool IsTicketInTracker(ulong ticket)
  {
   for(int i = 0; i < ArraySize(g_slTracker); i++)
     {
      if(g_slTracker[i].ticket == ticket)
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Get tracked SL for a ticket                                        |
//+------------------------------------------------------------------+
double GetTrackedSL(ulong ticket)
  {
   for(int i = 0; i < ArraySize(g_slTracker); i++)
     {
      if(g_slTracker[i].ticket == ticket)
         return g_slTracker[i].sl;
     }
   return -1;
  }

//+------------------------------------------------------------------+
//| Update tracked SL for a ticket                                     |
//+------------------------------------------------------------------+
void UpdateTrackedSL(ulong ticket, double newSL)
  {
   for(int i = 0; i < ArraySize(g_slTracker); i++)
     {
      if(g_slTracker[i].ticket == ticket)
        {
         g_slTracker[i].sl = newSL;
         return;
        }
     }
  }

//+------------------------------------------------------------------+
//| Send message to Telegram (JSON body)                               |
//+------------------------------------------------------------------+
bool SendTelegramMessage(string message)
  {
   string url = "https://api.telegram.org/bot" + InpBotToken + "/sendMessage";

   // Escape special JSON characters in message
   string escapedMsg = message;
   StringReplace(escapedMsg, "\\", "\\\\");
   StringReplace(escapedMsg, "\"", "\\\"");
   StringReplace(escapedMsg, "\n", "\\n");
   StringReplace(escapedMsg, "\r", "\\r");
   StringReplace(escapedMsg, "\t", "\\t");

   // Build JSON body
   string jsonBody = "{\"chat_id\":\"" + InpChatID + "\","
                     "\"text\":\"" + escapedMsg + "\","
                     "\"parse_mode\":\"HTML\"}";

   DebugPrint("--- SendTelegramMessage ---");
   DebugPrint("URL: " + url);
   DebugPrint("Chat ID: [" + InpChatID + "]");
   DebugPrint("JSON length: " + (string)StringLen(jsonBody));
   DebugPrint("JSON body: " + StringSubstr(jsonBody, 0, 200) + "...");

   char   data[];
   char   result[];
   string resultHeaders;

   int len = StringToCharArray(jsonBody, data, 0, WHOLE_ARRAY, CP_UTF8);
   DebugPrint("StringToCharArray returned: " + (string)len + " bytes");

   if(len > 0)
     {
      ArrayResize(data, len - 1);  // Remove null terminator
      DebugPrint("Data array size after trim: " + (string)ArraySize(data));
     }
   else
     {
      Print("ERROR: StringToCharArray returned 0!");
      return false;
     }

   string headers = "Content-Type: application/json\r\n";
   int timeout = 10000; // 10 seconds

   ResetLastError();
   DebugPrint("Calling WebRequest...");
   int res = WebRequest("POST", url, headers, timeout, data, result, resultHeaders);
   int error = GetLastError();

   DebugPrint("WebRequest returned: " + (string)res);
   DebugPrint("GetLastError: " + (string)error);

   if(res == -1)
     {
      Print("*** WEBREQUEST FAILED ***");
      Print("Error code: ", error);

      if(error == 4014)
        {
         Print("==========================================================");
         Print("ERROR 4014: URL NOT ALLOWED!");
         Print("FIX: Tools > Options > Expert Advisors");
         Print("     [✓] Allow WebRequest for listed URL");
         Print("     Add: https://api.telegram.org");
         Print("     Then RESTART MT5!");
         Print("==========================================================");
        }
      else if(error == 4060)
        {
         Print("ERROR 4060: Function not allowed. Check EA permissions.");
        }
      else
        {
         Print("Unknown WebRequest error. Code: ", error);
         Print("Make sure https://api.telegram.org is in allowed URLs");
        }
      return false;
     }

   string response = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
   DebugPrint("HTTP Response Code: " + (string)res);
   DebugPrint("Response Headers: " + resultHeaders);
   DebugPrint("Response Body: " + response);

   if(res == 200)
     {
      Print("✓ Telegram message sent OK");
      return true;
     }
   else
     {
      Print("*** TELEGRAM API ERROR ***");
      Print("HTTP Code: ", res);
      Print("Response: ", response);

      if(res == 401)
         Print("=> Bot Token is INVALID! Check your token.");
      else if(res == 400)
         Print("=> Bad request. Chat ID may be wrong or bot not in group.");
      else if(res == 403)
         Print("=> Bot is BLOCKED or not a member of the group. Add bot to group first.");
      else if(res == 404)
         Print("=> Bot not found. Token might be wrong.");

      return false;
     }
  }
//+------------------------------------------------------------------+
