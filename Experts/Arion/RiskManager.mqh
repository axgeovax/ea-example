//+------------------------------------------------------------------+
//|                                                 RiskManager.mqh  |
//|                        Arion - Gestion de Riesgo                 |
//|                        Autor: Alexy Hernandez                    |
//|                        Version: 1.0                              |
//|        Copyright (c) 2025 Alexy Hernandez. Todos los derechos    |
//|        reservados.                                               |
//|   * CORREGIDO: Limite de lote maximo configurable (InpMaxLot)    |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernandez. Todos los derechos reservados."
#property link      "https://github.com/axgeovax"
#property version   "1.0"
#property strict

#include "CorrelationEngine.mqh"

#ifndef __RISKMANAGER_MQH__
#define __RISKMANAGER_MQH__

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class RiskManager
  {
private:
   string               m_symbol;
   int                  m_volumeDigits;
   double               m_volumeStep;
   double               m_volumeMin;
   double               m_volumeMax;
   double               m_tickValue;
   double               m_tickSize;
   double               m_pointValuePerLot;
   CorrelationEngine*   m_corrEngine;

   double               m_maxLot;        // Limite maximo de lote por operacion

   bool                 LoadProperties();
   double               CalculateReductionFactor();

public:
                     RiskManager(string symbol = NULL, CorrelationEngine* corr = NULL);
                    ~RiskManager() { }

   bool                 UpdateProperties() { return LoadProperties(); }
   double               CalculateLots(double riskPercentage, double slDistancePoints);
   bool                 ValidateLot(double lot);
   void                 SetCorrelationEngine(CorrelationEngine* corr) { m_corrEngine = corr; }
   void                 SetMaxLot(double maxLot) { m_maxLot = MathMax(0.0, maxLot); }
   double               GetMaxLot() const { return m_maxLot; }
  };

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
RiskManager::RiskManager(string symbol, CorrelationEngine* corr)
  {
   m_symbol = (symbol == NULL) ? _Symbol : symbol;
   m_volumeDigits = 0;
   m_volumeStep = m_volumeMin = m_volumeMax = 0.0;
   m_tickValue = m_tickSize = m_pointValuePerLot = 0.0;
   m_corrEngine = corr;
   m_maxLot = 0.0;   // 0 = sin limite
   LoadProperties();
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool RiskManager::LoadProperties()
  {
   m_volumeStep = m_volumeMin = m_volumeMax = 0.0;
   m_tickValue = m_tickSize = m_pointValuePerLot = 0.0;
   m_volumeDigits = 0;

   if(!SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP, m_volumeStep) || m_volumeStep <= 0.0)
     { Print("Error [RiskManager]: Invalid SYMBOL_VOLUME_STEP for ", m_symbol); return false; }
   if(!SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN, m_volumeMin) || m_volumeMin <= 0.0)
     { Print("Error [RiskManager]: Invalid SYMBOL_VOLUME_MIN for ", m_symbol); return false; }
   if(!SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX, m_volumeMax) || m_volumeMax <= 0.0)
     { Print("Error [RiskManager]: Invalid SYMBOL_VOLUME_MAX for ", m_symbol); return false; }

   if(!SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE, m_tickValue) || m_tickValue <= 0.0)
     { Print("Error [RiskManager]: SYMBOL_TRADE_TICK_VALUE not available for ", m_symbol); return false; }
   if(!SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE, m_tickSize) || m_tickSize <= 0.0)
     { Print("Error [RiskManager]: SYMBOL_TRADE_TICK_SIZE not available for ", m_symbol); return false; }

   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = m_tickSize;
   m_pointValuePerLot = m_tickValue * (point / m_tickSize);

   int digits = 0;
   double step = m_volumeStep;
   while(step < 1.0 && digits < 8)
     {
      step *= 10.0;
      digits++;
     }
   m_volumeDigits = digits;
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double RiskManager::CalculateReductionFactor()
  {
   if(m_corrEngine == NULL)
      return 1.0;

   double minFactor = 1.0;
   int total = PositionsTotal();

   for(int i = 0; i < total; i++)
     {
      if(!PositionSelectByTicket(PositionGetTicket(i)))
         continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      if(sym == m_symbol)
         continue;

      double currentFactor = m_corrEngine.GetAdaptiveReductionFactor(m_symbol, sym);
      minFactor = MathMin(minFactor, currentFactor);
     }

   return minFactor;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double RiskManager::CalculateLots(double riskPercentage, double slDistancePoints)
  {
   if(riskPercentage <= 0.0 || slDistancePoints <= 0.0)
     { Print("Error [RiskManager]: Risk% and SL distance must be > 0"); return 0.0; }
   if(m_pointValuePerLot <= 0.0)
     { Print("Error [RiskManager]: Symbol properties not initialized."); return 0.0; }

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0)
     {
      Print("Error [RiskManager]: Invalid account equity");
      return 0.0;
     }

   double riskCapital = equity * (riskPercentage / 100.0);
   double riskPerLot = slDistancePoints * m_pointValuePerLot;
   if(riskPerLot <= 0.0)
      return 0.0;

   double rawLot = riskCapital / riskPerLot;
   double factor = CalculateReductionFactor();
   rawLot *= factor;

   double normalizedLot = NormalizeDouble(MathFloor(rawLot / m_volumeStep) * m_volumeStep, m_volumeDigits);

// Aplicar limite maximo de lote si esta configurado
   if(m_maxLot > 0.0 && normalizedLot > m_maxLot)
     {
      Print("⚠ Lote calculado (", normalizedLot, ") supera el maximo permitido (", m_maxLot, "). Ajustando.");
      normalizedLot = m_maxLot;
     }

   if(normalizedLot < m_volumeMin)
     {
      Print("Warning [RiskManager]: Calculated lot (", normalizedLot, ") < min (", m_volumeMin, "). Trade discarded.");
      return 0.0;
     }
   if(normalizedLot > m_volumeMax)
     {
      Print("Warning [RiskManager]: Calculated lot exceeds max. Clamped to ", m_volumeMax);
      normalizedLot = m_volumeMax;
     }
   return normalizedLot;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool RiskManager::ValidateLot(double lot)
  {
   if(m_volumeStep <= 0.0)
      return false;
   double normalized = NormalizeDouble(MathFloor(lot / m_volumeStep) * m_volumeStep, m_volumeDigits);
   bool stepOk = (MathAbs(normalized - lot) < 1e-10);
   bool rangeOk = (lot >= m_volumeMin && lot <= m_volumeMax);
   bool maxOk = (m_maxLot == 0.0 || lot <= m_maxLot);
   return stepOk && rangeOk && maxOk;
  }

#endif // __RISKMANAGER_MQH__
//+------------------------------------------------------------------+
