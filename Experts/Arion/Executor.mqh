//+------------------------------------------------------------------+
//|                                                  Executor.mqh    |
//|                        Arion - Ejecucion Asincrona Avanzada      |
//|   Llenado adaptativo, Slippage dinamico, Margen variable,        |
//|   BE/Trailing por pips, Back‑off selectivo                       |
//|   * CORREGIDO: Slippage ampliado para activos volatiles.         |
//|                        Autor: Alexy Hernandez                    |
//|                        Version: 1.0                              |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernandez. Todos los derechos reservados."
#property link      "https://github.com/axgeovax"
#property version   "1.0"
#property strict

#include <Trade\Trade.mqh>
#include "NewsFilter.mqh"
#include "Logger.mqh"

#ifndef __EXECUTOR_MQH__
#define __EXECUTOR_MQH__

enum ENUM_ARION_ORDER_STATE
  {
   ARION_ORDER_STATE_NONE,
   ARION_ORDER_STATE_PENDING,
   ARION_ORDER_STATE_FILLED,
   ARION_ORDER_STATE_ERROR
  };

struct PendingOrder
  {
   MqlTradeRequest   request;
   datetime          attemptTime;
   datetime          expiration;
  };

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class Executor
  {
private:
   string                  m_symbol;
   int                     m_maxRetries;
   long                    m_magicNumber;
   string                  m_blockedAssets[];
   datetime                m_blockTime[];
   int                     m_totalBlocked;
   CTrade                  m_trade;
   ENUM_ARION_ORDER_STATE  m_orderState;
   int                     m_currentRetries;
   bool                    m_orderInFlight;
   datetime                m_sendTime;
   datetime                m_lastBECheck;
   datetime                m_lastTrailCheck;

   int                     m_asyncTimeout;
   int                     m_consecutiveTimeouts;

   double                  m_lastBEPrice;
   double                  m_lastTrailPrice;
   double                  m_trailStepPips;
   double                  m_trailDistancePips;

   int                     m_handleATR_M1;
   int                     m_minPipsDisplacement;

   NewsFilter*             m_newsFilter;
   bool                    m_reduceLotDuringNews;
   PendingOrder            m_pendingOrders[];
   int                     m_pendingCount;
   int                     m_pendingExpirationSeconds;

   double                  m_spreadBuffer[20];
   int                     m_spreadBufferIdx;
   int                     m_spreadBufferCount;
   double                  m_avgSpread;

   double                  m_maxSafetyFactor;

   double                  GetUpdatedPrice(ENUM_ORDER_TYPE type);
   bool                    IsBlocked();
   void                    BlockAsset(int seconds = 60);
   int                     CalculateDynamicSlippage();
   double                  GetSafetyMarginFactor();
   double                  GetATR_M1();
   ENUM_ORDER_TYPE_FILLING GetFillingMode();

   void                    UpdateSpreadAverage();
   bool                    IsNewsLockoutActive();
   void                    RetryPendingOrders();

public:
                     Executor(string symbol = NULL, long magicBase = 202400, double maxSafetyFactor = 2.0);
                    ~Executor();

   bool                    Initialize();
   bool                    SendMarketOrder(ENUM_ORDER_TYPE type, double lot, double sl, double tp, string comment = "");
   void                    ProcessTransaction(const MqlTradeTransaction& trans,
         const MqlTradeRequest& request,
         const MqlTradeResult& result);
   void                    ManageBreakeven(double activationRatio = 1.0, double extraPoints = 5.0);
   void                    ManageTrailingStop(double trailStartRatio = 1.5,
         double trailDistancePips = 50.0,
         double trailStepPips = 5.0,
         double trailATRMultiplier = 0.0);
   void                    ClearLocks();
   void                    SetAsyncTimeout(int seconds) { m_asyncTimeout = (seconds > 0) ? seconds : 30; }
   string                  GetSymbol() const { return m_symbol; }
   ENUM_ARION_ORDER_STATE  GetState() const { return m_orderState; }
   bool                    HasOrderInFlight() const { return m_orderInFlight; }

   double                  GetCurrentATR() { return GetATR_M1(); }
   void                    SetMinPipsDisplacement(int pips) { m_minPipsDisplacement = pips; }

   void                    SetNewsFilter(NewsFilter* filter) { m_newsFilter = filter; }
   void                    SetReduceLotDuringNews(bool enable) { m_reduceLotDuringNews = enable; }

   void                    RetryClosedMarketOrders() { RetryPendingOrders(); }
  };

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Executor::Executor(string symbol, long magicBase, double maxSafetyFactor = 2.0)
  {
   m_symbol = (symbol == NULL) ? _Symbol : symbol;
   m_maxRetries = 3;
   m_magicNumber = magicBase;
   m_totalBlocked = 0;
   ArrayResize(m_blockedAssets, 0);
   ArrayResize(m_blockTime, 0);
   m_orderState = ARION_ORDER_STATE_NONE;
   m_currentRetries = 0;
   m_orderInFlight = false;
   m_sendTime = 0;
   m_lastBECheck = 0;
   m_lastTrailCheck = 0;
   m_asyncTimeout = 30;
   m_consecutiveTimeouts = 0;
   m_lastBEPrice = 0;
   m_lastTrailPrice = 0;
   m_trailStepPips = 5.0;
   m_trailDistancePips = 50.0;
   m_handleATR_M1 = INVALID_HANDLE;
   m_minPipsDisplacement = 2;
   m_newsFilter = NULL;
   m_reduceLotDuringNews = false;
   ArrayResize(m_pendingOrders, 0);
   m_pendingCount = 0;
   m_pendingExpirationSeconds = 86400;
   ArrayInitialize(m_spreadBuffer, 0.0);
   m_spreadBufferIdx = 0;
   m_spreadBufferCount = 0;
   m_maxSafetyFactor = maxSafetyFactor;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Executor::~Executor()
  {
   if(m_handleATR_M1 != INVALID_HANDLE)
      IndicatorRelease(m_handleATR_M1);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool Executor::Initialize()
  {
   if(!SymbolSelect(m_symbol, true))
     {
      Print("Error [Executor]: Symbol ", m_symbol, " not available.");
      return false;
     }
   m_handleATR_M1 = iATR(m_symbol, PERIOD_M1, 14);
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Executor::UpdateSpreadAverage()
  {
   long spread = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
   m_spreadBuffer[m_spreadBufferIdx] = (double)spread;
   m_spreadBufferIdx = (m_spreadBufferIdx + 1) % 20;
   if(m_spreadBufferCount < 20)
      m_spreadBufferCount++;
   double sum = 0.0;
   for(int i = 0; i < m_spreadBufferCount; i++)
      sum += m_spreadBuffer[i];
   m_avgSpread = sum / m_spreadBufferCount;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool Executor::IsNewsLockoutActive()
  {
   if(m_newsFilter == NULL)
      return false;
   double dummyFactor;
   return m_newsFilter.IsLockoutPeriod(m_symbol, dummyFactor);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double Executor::GetUpdatedPrice(ENUM_ORDER_TYPE type)
  {
   return (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(m_symbol, SYMBOL_ASK)
          : SymbolInfoDouble(m_symbol, SYMBOL_BID);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool Executor::IsBlocked()
  {
   for(int i = 0; i < m_totalBlocked; i++)
     {
      if(m_blockedAssets[i] == m_symbol)
        {
         if(TimeCurrent() < m_blockTime[i])
            return true;
         for(int j = i; j < m_totalBlocked - 1; j++)
           {
            m_blockedAssets[j] = m_blockedAssets[j+1];
            m_blockTime[j] = m_blockTime[j+1];
           }
         m_totalBlocked--;
         ArrayResize(m_blockedAssets, m_totalBlocked);
         ArrayResize(m_blockTime, m_totalBlocked);
         return false;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Executor::BlockAsset(int seconds)
  {
   if(IsBlocked())
      return;
   ArrayResize(m_blockedAssets, m_totalBlocked + 1);
   ArrayResize(m_blockTime, m_totalBlocked + 1);
   m_blockedAssets[m_totalBlocked] = m_symbol;
   m_blockTime[m_totalBlocked] = TimeCurrent() + seconds;
   m_totalBlocked++;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Executor::ClearLocks()
  {
   for(int i = m_totalBlocked - 1; i >= 0; i--)
     {
      if(TimeCurrent() >= m_blockTime[i])
        {
         for(int j = i; j < m_totalBlocked - 1; j++)
           {
            m_blockedAssets[j] = m_blockedAssets[j+1];
            m_blockTime[j] = m_blockTime[j+1];
           }
         m_totalBlocked--;
        }
     }
   ArrayResize(m_blockedAssets, m_totalBlocked);
   ArrayResize(m_blockTime, m_totalBlocked);

   if(m_orderInFlight && m_sendTime > 0 && TimeCurrent() - m_sendTime > m_asyncTimeout)
     {
      m_consecutiveTimeouts++;
      Print("⚠ [Executor] Async order timeout #", m_consecutiveTimeouts, " for ", m_symbol);
      m_orderInFlight = false;
      m_orderState = ARION_ORDER_STATE_ERROR;
      m_currentRetries = 0;
      int seconds = 60 * MathMin(1 << MathMin(m_consecutiveTimeouts-1, 3), 5);
      BlockAsset(seconds);
     }

   RetryPendingOrders();
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Executor::RetryPendingOrders()
  {
   if(m_pendingCount == 0)
      return;

   datetime now = TimeCurrent();
   ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_MODE);
   bool marketOpen = (tradeMode == SYMBOL_TRADE_MODE_FULL ||
                      tradeMode == SYMBOL_TRADE_MODE_LONGONLY ||
                      tradeMode == SYMBOL_TRADE_MODE_SHORTONLY);

   for(int i = m_pendingCount - 1; i >= 0; i--)
     {
      if(now > m_pendingOrders[i].expiration)
        {
         for(int j = i; j < m_pendingCount - 1; j++)
            m_pendingOrders[j] = m_pendingOrders[j+1];
         m_pendingCount--;
         ArrayResize(m_pendingOrders, m_pendingCount);
         continue;
        }

      if(!marketOpen)
         continue;

      MqlTradeResult result;
      if(OrderSendAsync(m_pendingOrders[i].request, result))
        {
         for(int j = i; j < m_pendingCount - 1; j++)
            m_pendingOrders[j] = m_pendingOrders[j+1];
         m_pendingCount--;
         ArrayResize(m_pendingOrders, m_pendingCount);
        }
      else
        {
         if(result.retcode != TRADE_RETCODE_MARKET_CLOSED)
           {
            for(int j = i; j < m_pendingCount - 1; j++)
               m_pendingOrders[j] = m_pendingOrders[j+1];
            m_pendingCount--;
            ArrayResize(m_pendingOrders, m_pendingCount);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int Executor::CalculateDynamicSlippage()
  {
   double atr = GetATR_M1();
   if(atr <= 0)
      return 30;
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   if(point <= 0)
      return 30;
   int slip = (int)(0.5 * atr / point);   // factor 0.5 en lugar de 0.3 para cubrir mas volatilidad
   if(slip < 10)
      slip = 10;
   if(slip > 200)
      slip = 200;             // ampliado para activos volatiles como XAU
   return slip;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double Executor::GetATR_M1()
  {
   if(m_handleATR_M1 == INVALID_HANDLE)
      m_handleATR_M1 = iATR(m_symbol, PERIOD_M1, 14);
   if(m_handleATR_M1 != INVALID_HANDLE)
     {
      double buf[1];
      if(CopyBuffer(m_handleATR_M1, 0, 0, 1, buf) == 1)
         return buf[0];
     }
   return 0.0;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double Executor::GetSafetyMarginFactor()
  {
   double base = 1.2;
   double atr = GetATR_M1();
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   if(atr > 0 && point > 0)
     {
      int atrPoints = (int)(atr / point);
      if(atrPoints > 50)
         base += 0.3;
      else
         if(atrPoints > 20)
            base += 0.2;
     }
   if(PositionsTotal() > 5)
      base += 0.2;
   double marginFree = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double marginUsed = AccountInfoDouble(ACCOUNT_MARGIN);
   if(marginFree > 0 && marginUsed > 0 && marginFree < marginUsed * 2)
      base += 0.3;
   return MathMin(base, m_maxSafetyFactor);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING Executor::GetFillingMode()
  {
   if(m_currentRetries == 0)
      return ORDER_FILLING_FOK;
   else
      if(m_currentRetries == 1)
         return ORDER_FILLING_IOC;
      else
         return ORDER_FILLING_RETURN;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool Executor::SendMarketOrder(ENUM_ORDER_TYPE type, double lot, double sl, double tp, string comment)
  {
   if(IsBlocked())
     {
      Print("Error [Executor]: ", m_symbol, " is blocked.");
      return false;
     }
   if(lot <= 0.0)
      return false;
   if(m_orderInFlight)
     {
      Print("Error [Executor]: An order is already in flight for ", m_symbol);
      return false;
     }

   if(m_reduceLotDuringNews && IsNewsLockoutActive())
     {
      lot *= 0.5;
     }

   double marginFree = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double marginReq = 0.0;
   double price = GetUpdatedPrice(type);
   if(price <= 0.0)
      return false;
   if(!OrderCalcMargin(type, m_symbol, lot, price, marginReq))
     { Print("Error [Executor]: Could not calculate margin."); return false; }
   double safetyFactor = GetSafetyMarginFactor();
   if(marginFree < marginReq * safetyFactor)
     {
      Print("Error [Executor]: Insufficient margin");
      BlockAsset(300);
      return false;
     }

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = m_symbol;
   request.volume    = lot;
   request.type      = type;
   request.deviation = CalculateDynamicSlippage();
   request.magic     = m_magicNumber;
   request.comment   = comment;
   request.type_filling = GetFillingMode();
   request.price     = price;

   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   if(type == ORDER_TYPE_BUY)
     {
      request.sl = (sl > 0) ? price - sl * point : 0;
      request.tp = (tp > 0) ? price + tp * point : 0;
     }
   else
     {
      request.sl = (sl > 0) ? price + sl * point : 0;
      request.tp = (tp > 0) ? price - tp * point : 0;
     }

   if(!OrderSendAsync(request, result))
     {
      Print("Error [Executor]: OrderSendAsync failed immediately. Retcode: ", result.retcode);
      return false;
     }

   m_orderInFlight = true;
   m_orderState = ARION_ORDER_STATE_PENDING;
   m_currentRetries = 0;
   m_sendTime = TimeCurrent();
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Executor::ProcessTransaction(const MqlTradeTransaction& trans,
                                  const MqlTradeRequest& request,
                                  const MqlTradeResult& result)
  {
   if(!m_orderInFlight)
      return;
   if(request.symbol != m_symbol || request.magic != m_magicNumber)
      return;

   switch(result.retcode)
     {
      case TRADE_RETCODE_DONE:
      case TRADE_RETCODE_DONE_PARTIAL:
         m_orderInFlight = false;
         m_orderState = ARION_ORDER_STATE_FILLED;
         m_consecutiveTimeouts = 0;
         Logger::LogTrade(m_symbol, "OPEN", result.order, result.price, result.volume, request.sl, request.tp);
         break;

      case TRADE_RETCODE_REQUOTE:
      case TRADE_RETCODE_PRICE_CHANGED:
      case TRADE_RETCODE_PRICE_OFF:
         if(++m_currentRetries >= m_maxRetries)
           {
            m_orderInFlight = false;
            m_orderState = ARION_ORDER_STATE_ERROR;
            BlockAsset(60);
           }
         else
           {
            double newPrice = GetUpdatedPrice((ENUM_ORDER_TYPE)request.type);
            if(newPrice > 0.0)
              {
               MqlTradeRequest newReq = request;
               MqlTradeResult  newRes;
               newReq.price = newPrice;
               newReq.deviation = CalculateDynamicSlippage();
               newReq.type_filling = GetFillingMode();
               if(OrderSendAsync(newReq, newRes))
                  m_sendTime = TimeCurrent();
               else
                 {
                  m_orderInFlight = false;
                  m_orderState = ARION_ORDER_STATE_ERROR;
                  BlockAsset(60);
                 }
              }
           }
         break;

      case TRADE_RETCODE_TIMEOUT:
      case TRADE_RETCODE_CONNECTION:
         if(++m_currentRetries < m_maxRetries)
           {
            Sleep(200);
            MqlTradeRequest newReq = request;
            MqlTradeResult  newRes;
            newReq.deviation = CalculateDynamicSlippage();
            newReq.type_filling = GetFillingMode();
            if(OrderSendAsync(newReq, newRes))
               m_sendTime = TimeCurrent();
            else
              {
               m_orderInFlight = false;
               m_orderState = ARION_ORDER_STATE_ERROR;
              }
           }
         else
           {
            m_orderInFlight = false;
            m_orderState = ARION_ORDER_STATE_ERROR;
            BlockAsset(60);
           }
         break;

      case TRADE_RETCODE_MARKET_CLOSED:
         if(m_pendingCount < 5)
           {
            ArrayResize(m_pendingOrders, m_pendingCount + 1);
            m_pendingOrders[m_pendingCount].request = request;
            m_pendingOrders[m_pendingCount].attemptTime = TimeCurrent();
            m_pendingOrders[m_pendingCount].expiration  = TimeCurrent() + m_pendingExpirationSeconds;
            m_pendingCount++;
           }
         m_orderInFlight = false;
         m_orderState = ARION_ORDER_STATE_ERROR;
         break;

      case TRADE_RETCODE_FROZEN:
      case TRADE_RETCODE_INVALID_FILL:
      case TRADE_RETCODE_LIMIT_VOLUME:
      case TRADE_RETCODE_NO_MONEY:
         m_orderInFlight = false;
         m_orderState = ARION_ORDER_STATE_ERROR;
         BlockAsset(60 * MathMin(1 << MathMin(m_consecutiveTimeouts, 3), 5));
         break;

      case TRADE_RETCODE_INVALID_STOPS:
         m_orderInFlight = false;
         m_orderState = ARION_ORDER_STATE_ERROR;
         BlockAsset(120);
         break;

      default:
         if(++m_currentRetries >= m_maxRetries)
           {
            m_orderInFlight = false;
            m_orderState = ARION_ORDER_STATE_ERROR;
            BlockAsset(60);
           }
         break;
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Executor::ManageBreakeven(double activationRatio, double extraPoints)
  {
   UpdateSpreadAverage();

   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
   long stopLevel = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double atrM1 = GetATR_M1();
   if(atrM1 <= 0 || point <= 0)
      return;

   bool newsActive = IsNewsLockoutActive();
   long currentSpread = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);

   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != m_symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != m_magicNumber)
         continue;

      if(newsActive && m_avgSpread > 0 && currentSpread > m_avgSpread * 1.5)
         continue;

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice  = PositionGetDouble(POSITION_PRICE_OPEN);
      double originalSL = PositionGetDouble(POSITION_SL);
      double originalTP = PositionGetDouble(POSITION_TP);
      if(originalSL <= 0)
         continue;

      double profitPoints = (posType == POSITION_TYPE_BUY) ? (bid - openPrice) / point
                            : (openPrice - ask) / point;
      if(profitPoints <= 0)
         continue;

      double atrPoints = atrM1 / point;
      if(profitPoints < activationRatio * atrPoints)
         continue;

      double newSL = openPrice + (posType == POSITION_TYPE_BUY ? extraPoints * point : -extraPoints * point);
      newSL = NormalizeDouble(newSL, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS));

      if((posType == POSITION_TYPE_BUY && newSL <= originalSL) ||
         (posType == POSITION_TYPE_SELL && newSL >= originalSL))
         continue;

      double currentPrice = (posType == POSITION_TYPE_BUY) ? bid : ask;
      double distanceToPrice = MathAbs(currentPrice - newSL) / point;
      if(distanceToPrice < stopLevel)
         continue;

      if(PositionSelectByTicket(ticket))
        {
         if(m_trade.PositionModify(ticket, newSL, originalTP))
            m_lastBEPrice = currentPrice;
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Executor::ManageTrailingStop(double trailStartRatio, double trailDistancePips, double trailStepPips, double trailATRMultiplier = 0.0)
  {
   UpdateSpreadAverage();

   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
   long stopLevel = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
   double atrM1 = GetATR_M1();
   if(atrM1 <= 0 || point <= 0)
      return;

   bool newsActive = IsNewsLockoutActive();
   long currentSpread = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);

   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != m_symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != m_magicNumber)
         continue;

      if(newsActive && m_avgSpread > 0 && currentSpread > m_avgSpread * 1.5)
         continue;

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice  = PositionGetDouble(POSITION_PRICE_OPEN);
      double originalSL = PositionGetDouble(POSITION_SL);
      double originalTP = PositionGetDouble(POSITION_TP);
      if(originalSL <= 0)
         continue;

      double currentPrice = (posType == POSITION_TYPE_BUY) ? bid : ask;
      double profitPoints = (posType == POSITION_TYPE_BUY) ? (currentPrice - openPrice) / point
                            : (openPrice - currentPrice) / point;
      if(profitPoints <= 0)
         continue;

      double atrPoints = atrM1 / point;
      if(profitPoints < trailStartRatio * atrPoints)
         continue;

      // Dynamic trailing distance: use ATR if multiplier > 0, otherwise use fixed pips
      double dynamicTrailDistance = (trailATRMultiplier > 0.0) ? atrPoints * trailATRMultiplier : trailDistancePips;

      double newSL;
      if(posType == POSITION_TYPE_BUY)
         newSL = currentPrice - dynamicTrailDistance * point;
      else
         newSL = currentPrice + dynamicTrailDistance * point;
      newSL = NormalizeDouble(newSL, digits);

      if(posType == POSITION_TYPE_BUY)
        {
         if(newSL <= originalSL + trailStepPips * point)
            continue;
        }
      else
        {
         if(newSL >= originalSL - trailStepPips * point)
            continue;
        }

      if(m_lastTrailPrice != 0)
        {
         double moveSinceLast = MathAbs(currentPrice - m_lastTrailPrice) / point;
         if(moveSinceLast < trailStepPips)
            continue;
        }

      m_lastTrailPrice = currentPrice;

      double distanceToPrice = MathAbs(currentPrice - newSL) / point;
      if(distanceToPrice < stopLevel)
         continue;

      if(PositionSelectByTicket(ticket))
        {
         m_trade.PositionModify(ticket, newSL, originalTP);
        }
     }
  }

#endif // __EXECUTOR_MQH__
//+------------------------------------------------------------------+
