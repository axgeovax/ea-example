//+------------------------------------------------------------------+
//|                                                 RiskManager.mqh  |
//|                        Arion - Gestión de Riesgo                 |
//|                        Autor: Alexy Hernández                    |
//|                        Versión: 1.0                              |
//|        Copyright (c) 2025 Alexy Hernández. Todos los derechos    |
//|        reservados.                                               |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernández. Todos los derechos reservados."
#property link      "https://github.com/axgeovax"
#property version   "1.0"
#property strict

#include "CorrelationEngine.mqh"

#ifndef __RISKMANAGER_MQH__
#define __RISKMANAGER_MQH__

//+------------------------------------------------------------------+
//| Clase RiskManager: calcula el tamaño de lote óptimo basado en     |
//| riesgo porcentual y ajusta por correlación con otras posiciones.  |
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

   //+------------------------------------------------------------------+
   //| Carga las propiedades del símbolo desde el servidor.               |
   //+------------------------------------------------------------------+
   bool                 LoadProperties();

   //+------------------------------------------------------------------+
   //| Calcula el factor de reducción por correlación con otras posiciones.|
   //+------------------------------------------------------------------+
   double               CalculateReductionFactor();

public:
   //+------------------------------------------------------------------+
   //| Constructor: inicializa el gestor para un símbolo.                 |
   //+------------------------------------------------------------------+
                     RiskManager(string symbol = NULL, CorrelationEngine* corr = NULL);
                    ~RiskManager() { }

   //+------------------------------------------------------------------+
   //| Actualiza las propiedades del símbolo (apalancamiento, etc.).      |
   //+------------------------------------------------------------------+
   bool                 UpdateProperties() { return LoadProperties(); }

   //+------------------------------------------------------------------+
   //| Calcula el lote normalizado según riesgo, SL y correlación.       |
   //+------------------------------------------------------------------+
   double               CalculateLots(double riskPercentage, double slDistancePoints);

   //+------------------------------------------------------------------+
   //| Verifica que un lote cumpla con los límites del bróker.           |
   //+------------------------------------------------------------------+
   bool                 ValidateLot(double lot);

   //+------------------------------------------------------------------+
   //| Asigna el motor de correlación externo.                           |
   //+------------------------------------------------------------------+
   void                 SetCorrelationEngine(CorrelationEngine* corr) { m_corrEngine = corr; }
  };

//+------------------------------------------------------------------+
//| Constructor                                                        |
//+------------------------------------------------------------------+
RiskManager::RiskManager(string symbol, CorrelationEngine* corr)
  {
   m_symbol = (symbol == NULL) ? _Symbol : symbol;
   m_volumeDigits = 0;
   m_volumeStep = m_volumeMin = m_volumeMax = 0.0;
   m_tickValue = m_tickSize = m_pointValuePerLot = 0.0;
   m_corrEngine = corr;
   LoadProperties();
  }

//+------------------------------------------------------------------+
//| Cargar propiedades del símbolo                                      |
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

   m_pointValuePerLot = m_tickValue / m_tickSize;

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
//| Calcular factor de reducción por correlación (adaptativo)         |
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

      double factor = m_corrEngine.GetAdaptiveReductionFactor(m_symbol, sym);
      if(factor < minFactor)
         minFactor = factor;
     }

   return minFactor;
  }

//+------------------------------------------------------------------+
//| Calcular lote                                                      |
//+------------------------------------------------------------------+
double RiskManager::CalculateLots(double riskPercentage, double slDistancePoints)
  {
   if(riskPercentage <= 0.0 || slDistancePoints <= 0.0)
     { Print("Error [RiskManager]: Risk% and SL distance must be > 0"); return 0.0; }
   if(m_pointValuePerLot <= 0.0)
     { Print("Error [RiskManager]: Symbol properties not initialized."); return 0.0; }

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0.0)
     {
      Print("Error [RiskManager]: Invalid account balance");
      return 0.0;
     }

   double riskCapital = balance * (riskPercentage / 100.0);
   double riskPerLot = slDistancePoints * m_pointValuePerLot;
   if(riskPerLot <= 0.0)
      return 0.0;

   double rawLot = riskCapital / riskPerLot;

   double factor = CalculateReductionFactor();
   rawLot *= factor;

   double normalizedLot = MathFloor(rawLot / m_volumeStep) * m_volumeStep;
   normalizedLot = NormalizeDouble(normalizedLot, m_volumeDigits);

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
//| Validar lote                                                       |
//+------------------------------------------------------------------+
bool RiskManager::ValidateLot(double lot)
  {
   if(m_volumeStep <= 0.0)
      return false;
   double normalized = MathFloor(lot / m_volumeStep) * m_volumeStep;
   normalized = NormalizeDouble(normalized, m_volumeDigits);
   return (MathAbs(normalized - lot) < 1e-10) && (lot >= m_volumeMin) && (lot <= m_volumeMax);
  }

#endif // __RISKMANAGER_MQH__
//+------------------------------------------------------------------+
