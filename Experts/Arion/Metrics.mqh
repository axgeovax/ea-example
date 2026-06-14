//+------------------------------------------------------------------+
//|                                                  Metrics.mqh     |
//|                        Arion - Métricas de Trading               |
//|                        Autor: Alexy Hernández                    |
//|                        Versión: 1.0                              |
//|        Copyright (c) 2025 Alexy Hernández. Todos los derechos    |
//|        reservados.                                               |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernández. Todos los derechos reservados."
#property link      "https://github.com/axgeovax"
#property version   "1.0"
#property strict

#ifndef __METRICS_MQH__
#define __METRICS_MQH__

//+------------------------------------------------------------------+
//| Estructura que representa el resultado de una operación cerrada   |
//+------------------------------------------------------------------+
struct TradeResult
  {
   double            profit;     // ganancia neta de la operación
   double            balance;    // balance después de la operación
   datetime          closeTime;
  };

//+------------------------------------------------------------------+
//| Clase Metrics: funciones estáticas para calcular indicadores de   |
//| rendimiento sobre un array de operaciones cerradas.              |
//+------------------------------------------------------------------+
class Metrics
  {
public:
   //+------------------------------------------------------------------+
   //| Calcula el Sharpe Ratio anualizado (252 días).                     |
   //+------------------------------------------------------------------+
   static double     CalculateSharpeRatio(TradeResult &trades[]);

   //+------------------------------------------------------------------+
   //| Calcula el Profit Factor (ganancias / pérdidas).                   |
   //+------------------------------------------------------------------+
   static double     CalculateProfitFactor(TradeResult &trades[]);

   //+------------------------------------------------------------------+
   //| Calcula el máximo drawdown relativo.                              |
   //+------------------------------------------------------------------+
   static double     CalculateMaxDrawdown(TradeResult &trades[]);

   //+------------------------------------------------------------------+
   //| Calcula la expectancia matemática (promedio de profit por trade). |
   //+------------------------------------------------------------------+
   static double     CalculateExpectancy(TradeResult &trades[]);

   //+------------------------------------------------------------------+
   //| Calcula la tasa de aciertos (win rate) en porcentaje.            |
   //+------------------------------------------------------------------+
   static double     CalculateWinRate(TradeResult &trades[]);
  };

//+------------------------------------------------------------------+
//| Sharpe Ratio                                                       |
//+------------------------------------------------------------------+
double Metrics::CalculateSharpeRatio(TradeResult &trades[])
  {
   int n = ArraySize(trades);
   if(n < 2)
      return 0.0;

   double sumRet = 0.0, sumRet2 = 0.0;
   for(int i = 0; i < n; i++)
     {
      double ret = trades[i].profit;
      sumRet += ret;
      sumRet2 += ret * ret;
     }
   double mean = sumRet / n;
   double variance = (sumRet2 / n) - (mean * mean);
   if(variance <= 0)
      return 0.0;
   double std = MathSqrt(variance);
   if(std == 0.0)
      return 0.0;
   return mean / std * MathSqrt(252);
  }

//+------------------------------------------------------------------+
//| Profit Factor                                                      |
//+------------------------------------------------------------------+
double Metrics::CalculateProfitFactor(TradeResult &trades[])
  {
   double gain = 0.0, loss = 0.0;
   for(int i = 0; i < ArraySize(trades); i++)
     {
      if(trades[i].profit > 0)
         gain += trades[i].profit;
      else
         loss -= trades[i].profit;
     }
   if(loss == 0.0)
      return 0.0;
   return gain / loss;
  }

//+------------------------------------------------------------------+
//| Max Drawdown                                                       |
//+------------------------------------------------------------------+
double Metrics::CalculateMaxDrawdown(TradeResult &trades[])
  {
   int n = ArraySize(trades);
   if(n == 0)
      return 0.0;
   double maxDD = 0.0, peak = trades[0].balance;
   for(int i = 1; i < n; i++)
     {
      if(trades[i].balance > peak)
         peak = trades[i].balance;
      double dd = (peak - trades[i].balance) / peak;
      if(dd > maxDD)
         maxDD = dd;
     }
   return maxDD;
  }

//+------------------------------------------------------------------+
//| Expectancy                                                         |
//+------------------------------------------------------------------+
double Metrics::CalculateExpectancy(TradeResult &trades[])
  {
   int n = ArraySize(trades);
   if(n == 0)
      return 0.0;
   double sum = 0.0;
   for(int i = 0; i < n; i++)
      sum += trades[i].profit;
   return sum / n;
  }

//+------------------------------------------------------------------+
//| Win Rate                                                           |
//+------------------------------------------------------------------+
double Metrics::CalculateWinRate(TradeResult &trades[])
  {
   int n = ArraySize(trades), wins = 0;
   for(int i = 0; i < n; i++)
      if(trades[i].profit > 0)
         wins++;
   return (n > 0) ? (double)wins / n : 0.0;
  }

#endif // __METRICS_MQH__
//+------------------------------------------------------------------+
