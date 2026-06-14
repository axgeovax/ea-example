//+------------------------------------------------------------------+
//|                                               SignalFilter.mqh   |
//|                        Arion - Filtro Adaptativo                 |
//|                        Autor: Alexy Hernández                    |
//|                        Versión: 1.0                              |
//|        Copyright (c) 2025 Alexy Hernández. Todos los derechos    |
//|        reservados.                                               |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernández. Todos los derechos reservados."
#property link      "https://github.com/axgeovax"
#property version   "1.0"
#property strict

#ifndef __SIGNALFILTER_MQH__
#define __SIGNALFILTER_MQH__

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class SignalFilter
  {
private:
   string            m_symbol;

public:
                     SignalFilter(string symbol = NULL);
                    ~SignalFilter() {}

   double            ProcessSignal(int macroDirection,
                                   double probONNX,
                                   double probKNN,
                                   bool zoneMitigated,
                                   double mitigationRatio,
                                   double relativeVolatility);

   bool              PassHardFilters(long spread, int maxTrades);
  };

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
SignalFilter::SignalFilter(string symbol)
  {
   m_symbol = (symbol == NULL) ? _Symbol : symbol;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double SignalFilter::ProcessSignal(int macroDirection,
                                   double probONNX,
                                   double probKNN,
                                   bool zoneMitigated,
                                   double mitigationRatio,
                                   double relativeVolatility)
  {
   double weightONNX     = InpWeightONNX;
   double weightKNN      = InpWeightKNN;
   double weightSMC      = InpWeightSMC;
   double weightContext  = InpWeightContext;

   double transferFactor = 0.0;
   if(relativeVolatility > 2.0 || relativeVolatility < 0.3)
      transferFactor = 0.4;
   else
      if(relativeVolatility >= 0.5 && relativeVolatility <= 1.5)
         transferFactor = 0.0;

   double delta = weightKNN * transferFactor;
   weightKNN -= delta;
   weightSMC += delta;

   double scoreONNX = probONNX * weightONNX;

   double probKNNNorm = (probKNN + 1.0) / 2.0;
   double scoreKNN = probKNNNorm * weightKNN;

   double scoreSMC = zoneMitigated ? mitigationRatio * weightSMC : 0.0;

   double scoreContext = 0.0;
   if(relativeVolatility > 0.5 && relativeVolatility < 2.0)
      scoreContext = weightContext;
   else
      if(relativeVolatility > 0.3 && relativeVolatility <= 0.5)
         scoreContext = weightContext * 0.5;
      else
         if(relativeVolatility >= 2.0 && relativeVolatility <= 3.0)
            scoreContext = weightContext * 0.5;

   double concordance = 1.0 - MathAbs(probONNX - probKNNNorm);
   double concordanceFactor;
   if(concordance > 0.7)
      concordanceFactor = 1.0 + (concordance - 0.7) * 0.5;
   else
      if(concordance < 0.3)
         concordanceFactor = 0.5 + concordance * 1.67;
      else
         concordanceFactor = 1.0;

   double scoreAI = (scoreONNX + scoreKNN) * concordanceFactor;

   return scoreAI + scoreSMC + scoreContext;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool SignalFilter::PassHardFilters(long spread, int maxTrades)
  {
   if(spread > InpMaxSpreadPoints)
      return false;

   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
     {
      if(PositionSelectByTicket(PositionGetTicket(i)))
        {
         if(PositionGetString(POSITION_SYMBOL) == m_symbol)
            count++;
        }
     }
   return (count < maxTrades);
  }

#endif // __SIGNALFILTER_MQH__
//+------------------------------------------------------------------+
