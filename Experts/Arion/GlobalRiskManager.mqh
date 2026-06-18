//+------------------------------------------------------------------+
//|                                          GlobalRiskManager.mqh   |
//|                        Arion - Gestion Riesgo Global             |
//|            * SIN creditos diarios. Solo DD y limites de trades   |
//|                        Autor: Alexy Hernandez                    |
//|                        Version: 1.0                              |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernandez. Todos los derechos reservados."
#property link      "https://github.com/axgeovax"
#property version   "1.0"
#property strict

#include <Trade\Trade.mqh>

#ifndef __GLOBALRISKMANAGER_MQH__
#define __GLOBALRISKMANAGER_MQH__

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class GlobalRiskManager
  {
private:
   double            m_maxDailyLoss;
   int               m_maxGlobalTrades;
   double            m_trailingStopPct;
   bool              m_closeAllOnStop;

   double            m_dayStartEquity;    // equity al inicio del dia (calculado a partir del balance)
   int               m_currentDay;
   double            m_peakEquity;
   double            m_trailingStopLevel;
   CTrade            m_trade;

   long              m_magicBase;
   int               m_magicCount;

   // Contador global de operaciones (ya no hay créditos diarios)
   static const string   COUNTER_FILE;
   static const string   LOCK_FILE;
   static const string   COUNTER_LOCAL;
   static const int      LOCK_TIMEOUT_SEC;
   int               m_lockHandle;

   void              ResetDaily();
   void              UpdateTrailingStop();

   bool              AcquireLock();
   void              ReleaseLock();

   void              IncrementGlobalTrades();
   void              DecrementGlobalTrades();
   int               GetGlobalTradeCount();

   double            CalculateDayStartBalance();

public:
                     GlobalRiskManager();
                    ~GlobalRiskManager() { ReleaseLock(); }

   void              Configure(double maxDailyLoss, int maxGlobalTrades,
                               double trailingStopPct, bool closeAllOnStop);
   void              SetMagicRange(long magicBase, int count) { m_magicBase = magicBase; m_magicCount = count; }
   bool              CanOpenTrade();
   void              ExecuteEmergencyClose();
   void              Update();
   double            GetDayStartEquity() const { return m_dayStartEquity; }

   bool              SaveState(string fileName);
   bool              LoadState(string fileName);

   struct LockGuard
     {
   private:
      GlobalRiskManager* m_manager;
      bool               m_acquired;
   public:
                     LockGuard(GlobalRiskManager* mgr) : m_manager(mgr), m_acquired(false)
        {
         if(m_manager != NULL)
            m_acquired = m_manager.AcquireLock();
        }
                    ~LockGuard()
        {
         if(m_acquired && m_manager != NULL)
            m_manager.ReleaseLock();
        }
      bool           IsLocked() const { return m_acquired; }
     };
  };

const string GlobalRiskManager::COUNTER_FILE        = "Arion\\GlobalTrades.cnt";
const string GlobalRiskManager::LOCK_FILE           = "Arion\\GlobalTrades.lock";
const string GlobalRiskManager::COUNTER_LOCAL       = "Arion_GlobalTrades.cnt";  // fallback COMMON
const int    GlobalRiskManager::LOCK_TIMEOUT_SEC    = 2;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
GlobalRiskManager::GlobalRiskManager()
  {
   m_maxDailyLoss = 0.0;
   m_maxGlobalTrades = 0;
   m_trailingStopPct = 0.0;
   m_closeAllOnStop = false;
   m_dayStartEquity = 0.0;
   m_currentDay = 0;
   m_peakEquity = 0.0;
   m_trailingStopLevel = 0.0;
   m_magicBase = 0;
   m_magicCount = 0;
   m_lockHandle = INVALID_HANDLE;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void GlobalRiskManager::Configure(double maxDailyLoss, int maxGlobalTrades,
                                  double trailingStopPct, bool closeAllOnStop)
  {
   m_maxDailyLoss = maxDailyLoss;
   m_maxGlobalTrades = maxGlobalTrades;
   m_trailingStopPct = trailingStopPct;
   m_closeAllOnStop = closeAllOnStop;
   ResetDaily();
   if(m_peakEquity > 0.0 && m_trailingStopPct > 0.0)
      m_trailingStopLevel = m_peakEquity * (1.0 - m_trailingStopPct / 100.0);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GlobalRiskManager::CalculateDayStartBalance()
  {
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double todayClosedProfit = 0.0;

   datetime dayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   HistorySelect(dayStart, TimeCurrent());
   int totalDeals = HistoryDealsTotal();
   for(int i = 0; i < totalDeals; i++)
     {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0)
         continue;
      long entry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
         todayClosedProfit += HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
     }

   double startBalance = currentBalance - todayClosedProfit;
   return MathMax(0.0, startBalance);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void GlobalRiskManager::ResetDaily()
  {
   double startBalance = CalculateDayStartBalance();
   m_dayStartEquity = startBalance;

   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   m_peakEquity = MathMax(m_dayStartEquity, currentEquity);
   if(m_trailingStopPct > 0.0)
      m_trailingStopLevel = m_peakEquity * (1.0 - m_trailingStopPct / 100.0);

   MqlDateTime dt;
   TimeCurrent(dt);
   m_currentDay = dt.day_of_year;

   if(!FileIsExist(COUNTER_FILE))
     {
      int h = FileOpen(COUNTER_FILE, FILE_WRITE | FILE_BIN);
      if(h != INVALID_HANDLE)
        {
         int zero = 0;
         FileWriteInteger(h, zero);
         FileClose(h);
        }
      else
        {
         h = FileOpen(COUNTER_LOCAL, FILE_WRITE | FILE_BIN | FILE_COMMON);
         if(h != INVALID_HANDLE)
           {
            int zero = 0;
            FileWriteInteger(h, zero);
            FileClose(h);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void GlobalRiskManager::UpdateTrailingStop()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(m_trailingStopPct > 0.0 && (m_trailingStopLevel <= 0.0 || m_peakEquity <= 0.0))
     {
      m_peakEquity = equity;
      m_trailingStopLevel = m_peakEquity * (1.0 - m_trailingStopPct / 100.0);
      return;
     }
   if(equity > m_peakEquity)
     {
      m_peakEquity = equity;
      m_trailingStopLevel = m_peakEquity * (1.0 - m_trailingStopPct / 100.0);
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool GlobalRiskManager::AcquireLock()
  {
   datetime start = TimeCurrent();
   while(TimeCurrent() - start < LOCK_TIMEOUT_SEC)
     {
      m_lockHandle = FileOpen(LOCK_FILE, FILE_WRITE | FILE_BIN);
      if(m_lockHandle != INVALID_HANDLE)
         return true;
      Sleep(25);
     }
   Print("⚠ GlobalRiskManager: could not acquire lock within timeout");
   return false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void GlobalRiskManager::ReleaseLock()
  {
   if(m_lockHandle != INVALID_HANDLE)
     {
      FileClose(m_lockHandle);
      m_lockHandle = INVALID_HANDLE;
      FileDelete(LOCK_FILE);
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int GlobalRiskManager::GetGlobalTradeCount()
  {
   if(m_magicBase == 0 || m_magicCount == 0)
      return PositionsTotal();
   
   int count = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(magic >= m_magicBase && magic < m_magicBase + m_magicCount)
         count++;
     }
   return count;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void GlobalRiskManager::IncrementGlobalTrades()
  {
   // No-op: counter now based on live positions
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void GlobalRiskManager::DecrementGlobalTrades()
  {
   // No-op: counter now based on live positions
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool GlobalRiskManager::CanOpenTrade()
  {
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.day_of_year != m_currentDay)
      ResetDaily();

   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(m_maxDailyLoss > 0.0 && m_dayStartEquity > 0.0)
     {
      double lossPct = (1.0 - currentEquity / m_dayStartEquity) * 100.0;
      if(lossPct >= m_maxDailyLoss)
        {
         Print("⚠ Daily loss limit reached: ", DoubleToString(lossPct, 2), "%");
         return false;
        }
     }

   UpdateTrailingStop();
   if(m_trailingStopPct > 0.0 && currentEquity < m_trailingStopLevel)
     {
      Print("⚠ Account trailing stop activated (equity ", DoubleToString(currentEquity, 2),
            " < ", DoubleToString(m_trailingStopLevel, 2), ")");
      if(m_closeAllOnStop)
         ExecuteEmergencyClose();
      return false;
     }

   int globalPositions = GetGlobalTradeCount();
   if(m_maxGlobalTrades > 0 && globalPositions >= m_maxGlobalTrades)
     {
      Print("⚠ Global trade limit reached (", globalPositions, "/", m_maxGlobalTrades, ")");
      return false;
     }

   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void GlobalRiskManager::ExecuteEmergencyClose()
  {
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(m_magicCount > 0)
        {
         long posMagic = PositionGetInteger(POSITION_MAGIC);
         if(posMagic < m_magicBase || posMagic >= m_magicBase + m_magicCount)
            continue;
        }
      if(!m_trade.PositionClose(ticket))
         Print("Error closing position ", ticket, ": ", GetLastError());
      else
        {
         Print("Position ", ticket, " closed by emergency stop.");
         DecrementGlobalTrades();
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void GlobalRiskManager::Update()
  {
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.day_of_year != m_currentDay)
      ResetDaily();
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool GlobalRiskManager::SaveState(string fileName)
  {
   string tmpFile = fileName + ".tmp";
   if(FileIsExist(tmpFile))
      FileDelete(tmpFile);
   int handle = FileOpen(tmpFile, FILE_BIN | FILE_WRITE);
   if(handle == INVALID_HANDLE)
      return false;
   FileWriteDouble(handle, m_dayStartEquity);
   FileWriteDouble(handle, m_peakEquity);
   FileWriteDouble(handle, m_trailingStopLevel);
   FileWriteInteger(handle, m_currentDay);
   FileWriteInteger(handle, 0);               // previously dailyCredits, now always 0
   FileWriteInteger(handle, 0);               // previously maxDailyCredits
   FileWriteDouble(handle, m_maxDailyLoss);
   FileWriteInteger(handle, m_maxGlobalTrades);
   FileWriteDouble(handle, m_trailingStopPct);
   FileWriteInteger(handle, m_closeAllOnStop ? 1 : 0);
   FileWriteLong(handle, m_magicBase);
   FileWriteInteger(handle, m_magicCount);
   FileClose(handle);
   if(FileIsExist(fileName))
      FileDelete(fileName);
   if(!FileMove(tmpFile, 0, fileName, 0))
      return false;
   Print("GlobalRiskManager state saved (safe) to ", fileName);
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool GlobalRiskManager::LoadState(string fileName)
  {
   if(!FileIsExist(fileName))
      return false;
   int handle = FileOpen(fileName, FILE_BIN | FILE_READ);
   if(handle == INVALID_HANDLE)
      return false;
   m_dayStartEquity   = FileReadDouble(handle);
   m_peakEquity       = FileReadDouble(handle);
   m_trailingStopLevel= FileReadDouble(handle);
   m_currentDay       = FileReadInteger(handle);
   /* int dummyCredits = */ FileReadInteger(handle);   // ignorar
   /* int dummyMax    = */ FileReadInteger(handle);   // ignorar
   m_maxDailyLoss     = FileReadDouble(handle);
   m_maxGlobalTrades  = FileReadInteger(handle);
   m_trailingStopPct  = FileReadDouble(handle);
   m_closeAllOnStop   = FileReadInteger(handle) != 0;
   m_magicBase        = FileReadLong(handle);
   m_magicCount       = FileReadInteger(handle);
   FileClose(handle);
   if(m_dayStartEquity <= 0.0 || m_peakEquity <= 0.0)
     { ResetDaily(); return true; }
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.day_of_year != m_currentDay)
      ResetDaily();
   else
     {
      m_dayStartEquity = CalculateDayStartBalance();
     }
   int h = FileOpen(COUNTER_FILE, FILE_WRITE | FILE_BIN);
   if(h != INVALID_HANDLE)
     {
      FileWriteInteger(h, 0);
      FileClose(h);
     }
   Print("GlobalRiskManager state loaded from ", fileName,
         " (dayStartEquity: ", DoubleToString(m_dayStartEquity, 2), ")");
   return true;
  }

#endif // __GLOBALRISKMANAGER_MQH__
//+------------------------------------------------------------------+
