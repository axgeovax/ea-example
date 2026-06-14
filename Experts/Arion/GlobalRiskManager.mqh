//+------------------------------------------------------------------+
//|                                          GlobalRiskManager.mqh   |
//|                        Arion - Gestión Riesgo Global             |
//|            Créditos diarios, cierre selectivo, trailing stop     |
//|                        Autor: Alexy Hernández                    |
//|                        Versión: 1.0                              |
//|        Copyright (c) 2025 Alexy Hernández. Todos los derechos    |
//|        reservados.                                               |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernández. Todos los derechos reservados."
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

   double            m_dayStartEquity;
   int               m_currentDay;
   double            m_peakEquity;
   double            m_trailingStopLevel;
   CTrade            m_trade;

   long              m_magicBase;
   int               m_magicCount;

   int               m_dailyCredits;
   int               m_maxDailyCredits;

   void              ResetDaily();
   void              UpdateTrailingStop();

public:
                     GlobalRiskManager();
                    ~GlobalRiskManager() {}

   void              Configure(double maxDailyLoss, int maxGlobalTrades,
                               double trailingStopPct, bool closeAllOnStop);
   void              SetMagicRange(long magicBase, int count) { m_magicBase = magicBase; m_magicCount = count; }
   void              SetMaxDailyCredits(int credits) { m_maxDailyCredits = credits; m_dailyCredits = credits; }
   bool              CanOpenTrade();
   void              ExecuteEmergencyClose();
   void              Update();
   double            GetDayStartEquity() const { return m_dayStartEquity; }
   bool              ConsumeCredit();
   void              ReturnCredit();
   int               GetAvailableCredits() const { return m_dailyCredits; }

   // --- Persistencia (Safe Save) ---
   bool              SaveState(string fileName);
   bool              LoadState(string fileName);
  };

//+------------------------------------------------------------------+
//| Constructor                                                        |
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
   m_dailyCredits = 0;
   m_maxDailyCredits = 3;
  }

//+------------------------------------------------------------------+
//| Configurar límites                                                 |
//+------------------------------------------------------------------+
void GlobalRiskManager::Configure(double maxDailyLoss, int maxGlobalTrades,
                                  double trailingStopPct, bool closeAllOnStop)
  {
   m_maxDailyLoss = maxDailyLoss;
   m_maxGlobalTrades = maxGlobalTrades;
   m_trailingStopPct = trailingStopPct;
   m_closeAllOnStop = closeAllOnStop;
   ResetDaily();
  }

//+------------------------------------------------------------------+
//| Reset diario                                                       |
//+------------------------------------------------------------------+
void GlobalRiskManager::ResetDaily()
  {
   m_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   m_peakEquity = m_dayStartEquity;
   m_trailingStopLevel = m_dayStartEquity * (1.0 - m_trailingStopPct / 100.0);
   m_dailyCredits = m_maxDailyCredits;
   MqlDateTime dt;
   TimeCurrent(dt);
   m_currentDay = dt.day_of_year;
  }

//+------------------------------------------------------------------+
//| Actualizar trailing stop                                           |
//+------------------------------------------------------------------+
void GlobalRiskManager::UpdateTrailingStop()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > m_peakEquity)
     {
      m_peakEquity = equity;
      m_trailingStopLevel = m_peakEquity * (1.0 - m_trailingStopPct / 100.0);
     }
  }

//+------------------------------------------------------------------+
//| ¿Se puede abrir una operación?                                     |
//+------------------------------------------------------------------+
bool GlobalRiskManager::CanOpenTrade()
  {
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.day_of_year != m_currentDay)
      ResetDaily();

   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

// 1. Límite diario de pérdidas
   if(m_maxDailyLoss > 0.0 && m_dayStartEquity > 0.0)
     {
      double lossPct = (1.0 - currentEquity / m_dayStartEquity) * 100.0;
      if(lossPct >= m_maxDailyLoss)
        {
         Print("⚠ Daily loss limit reached: ", DoubleToString(lossPct, 2), "%");
         return false;
        }
     }

// 2. Trailing stop de cuenta
   UpdateTrailingStop();
   if(m_trailingStopPct > 0.0 && currentEquity < m_trailingStopLevel)
     {
      Print("⚠ Account trailing stop activated (equity ", DoubleToString(currentEquity, 2),
            " < ", DoubleToString(m_trailingStopLevel, 2), ")");
      if(m_closeAllOnStop)
         ExecuteEmergencyClose();
      return false;
     }

// 3. Máximo de operaciones globales
   if(m_maxGlobalTrades > 0 && PositionsTotal() >= m_maxGlobalTrades)
      return false;

   return true;
  }

//+------------------------------------------------------------------+
//| Consumir un crédito                                                |
//+------------------------------------------------------------------+
bool GlobalRiskManager::ConsumeCredit()
  {
   if(m_dailyCredits <= 0)
      return false;
   m_dailyCredits--;
   return true;
  }

//+------------------------------------------------------------------+
//| Devolver un crédito                                                |
//+------------------------------------------------------------------+
void GlobalRiskManager::ReturnCredit()
  {
   if(m_dailyCredits < m_maxDailyCredits)
      m_dailyCredits++;
  }

//+------------------------------------------------------------------+
//| Cierre de emergencia selectivo (solo posiciones del EA)           |
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
         Print("Position ", ticket, " closed by emergency stop.");
     }
  }

//+------------------------------------------------------------------+
//| Actualizar (verificar cambio de día)                               |
//+------------------------------------------------------------------+
void GlobalRiskManager::Update()
  {
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.day_of_year != m_currentDay)
      ResetDaily();
  }

//+------------------------------------------------------------------+
//| Safe Save – Guardar en .tmp y renombrar                            |
//+------------------------------------------------------------------+
bool GlobalRiskManager::SaveState(string fileName)
  {
   string tmpFile = fileName + ".tmp";

// Eliminar temporal previo
   if(FileIsExist(tmpFile))
      FileDelete(tmpFile);

   int handle = FileOpen(tmpFile, FILE_BIN | FILE_WRITE);
   if(handle == INVALID_HANDLE)
     {
      Print("Error [GlobalRiskManager] creating temp file: ", GetLastError());
      return false;
     }

   FileWriteDouble(handle, m_dayStartEquity);
   FileWriteDouble(handle, m_peakEquity);
   FileWriteInteger(handle, m_currentDay);
   FileWriteInteger(handle, m_dailyCredits);
   FileWriteInteger(handle, m_maxDailyCredits);
   FileWriteDouble(handle, m_maxDailyLoss);
   FileWriteInteger(handle, m_maxGlobalTrades);
   FileWriteDouble(handle, m_trailingStopPct);
   FileWriteInteger(handle, m_closeAllOnStop ? 1 : 0);
   FileWriteLong(handle, m_magicBase);
   FileWriteInteger(handle, m_magicCount);
   FileClose(handle);

// Borrar el archivo final si existe y renombrar
   if(FileIsExist(fileName))
      FileDelete(fileName);

   if(!FileMove(tmpFile, 0, fileName, 0))
     {
      Print("Error [GlobalRiskManager] renaming temp file to ", fileName);
      return false;
     }

   Print("GlobalRiskManager state saved (safe) to ", fileName);
   return true;
  }

//+------------------------------------------------------------------+
//| Cargar estado                                                      |
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
   m_currentDay       = FileReadInteger(handle);
   m_dailyCredits     = FileReadInteger(handle);
   m_maxDailyCredits  = FileReadInteger(handle);
   m_maxDailyLoss     = FileReadDouble(handle);
   m_maxGlobalTrades  = FileReadInteger(handle);
   m_trailingStopPct = FileReadDouble(handle);
   m_closeAllOnStop   = FileReadInteger(handle) != 0;
   m_magicBase        = FileReadLong(handle);
   m_magicCount       = FileReadInteger(handle);
   FileClose(handle);

// Si el día actual no coincide, forzar reset diario
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.day_of_year != m_currentDay)
     {
      // Mantener créditos? Normalmente se reinician, así que llamamos a ResetDaily
      // pero conservando algunos parámetros de configuración
      double maxLoss = m_maxDailyLoss;
      int maxTrades = m_maxGlobalTrades;
      double trailPct = m_trailingStopPct;
      bool closeAll = m_closeAllOnStop;
      Configure(maxLoss, maxTrades, trailPct, closeAll);
     }

   Print("GlobalRiskManager state loaded from ", fileName,
         " (credits: ", m_dailyCredits, "/", m_maxDailyCredits, ")");
   return true;
  }

#endif // __GLOBALRISKMANAGER_MQH__
//+------------------------------------------------------------------+
