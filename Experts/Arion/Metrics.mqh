//+------------------------------------------------------------------+
//|                                                  Metrics.mqh     |
//|                        Arion - Metricas de Trading               |
//|                        Autor: Alexy Hernandez                    |
//|                        Version: 1.0                              |
//|        Copyright (c) 2025 Alexy Hernandez. Todos los derechos    |
//|        reservados.                                               |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernandez. Todos los derechos reservados."
#property link      "https://github.com/axgeovax"
#property version   "1.0"
#property strict

#ifndef __METRICS_MQH__
#define __METRICS_MQH__

struct TradeResult
  {
   double            profit;
   double            balance;
   datetime          closeTime;
  };

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class Metrics
  {
public:
   static double     CalculateSharpeRatio(const TradeResult &trades[]);
   static double     CalculateProfitFactor(const TradeResult &trades[]);
   static double     CalculateMaxDrawdown(const TradeResult &trades[]);
   static double     CalculateExpectancy(const TradeResult &trades[]);
   static double     CalculateWinRate(const TradeResult &trades[]);
   static double     CalculateSortinoRatio(const TradeResult &trades[], double targetReturn = 0.0);

private:
   static void       BuildDailyReturns(const TradeResult &trades[], double &returns[], int &validDays);
  };

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Metrics::BuildDailyReturns(const TradeResult &trades[], double &returns[], int &validDays)
  {
   int n = ArraySize(trades);
   if(n == 0)
     {
      ArrayResize(returns, 0);
      validDays = 0;
      return;
     }

   datetime firstDate = trades[0].closeTime;
   datetime lastDate  = trades[n-1].closeTime;
   double currentBalance = trades[0].balance - trades[0].profit;
   if(currentBalance <= 0)
      currentBalance = trades[0].balance;

   int totalDays = 0;
   datetime tempDay = firstDate;
   while(tempDay <= lastDate)
     {
      totalDays++;
      MqlDateTime dt;
      TimeToStruct(tempDay, dt);
      dt.hour = 0;
      dt.min = 0;
      dt.sec = 0;
      tempDay = StructToTime(dt) + 86400;
     }

   double dailyBalances[];
   ArrayResize(dailyBalances, totalDays);
   int dayIndex = 0, tradeIdx = 0;
   double lastBalance = currentBalance;
   tempDay = firstDate;

   while(dayIndex < totalDays)
     {
      datetime thisDay = tempDay;
      MqlDateTime dt;
      TimeToStruct(thisDay, dt);
      dt.hour = 0;
      dt.min = 0;
      dt.sec = 0;
      datetime nextDay = StructToTime(dt) + 86400;
      double dayBalance = lastBalance;
      while(tradeIdx < n && trades[tradeIdx].closeTime < nextDay)
        {
         dayBalance = trades[tradeIdx].balance;
         tradeIdx++;
        }
      dailyBalances[dayIndex] = dayBalance;
      lastBalance = dayBalance;
      dayIndex++;
      tempDay = nextDay;
     }

   ArrayResize(returns, totalDays - 1);
   validDays = 0;
   for(int i = 1; i < totalDays; i++)
      if(dailyBalances[i-1] > 0)
        {
         double ret = (dailyBalances[i] - dailyBalances[i-1]) / dailyBalances[i-1];
         returns[validDays++] = ret;
        }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double Metrics::CalculateSharpeRatio(const TradeResult &trades[])
  {
   int n = ArraySize(trades);
   if(n < 2)
     {
      Print("SharpeRatio: need at least 2 trades");
      return 0.0;
     }
   double dailyReturns[];
   int validDays;
   BuildDailyReturns(trades, dailyReturns, validDays);
   if(validDays < 2)
     {
      Print("SharpeRatio: not enough valid daily returns");
      return 0.0;
     }
   double sum = 0.0, sumSq = 0.0;
   for(int i = 0; i < validDays; i++)
     {
      sum += dailyReturns[i];
      sumSq += dailyReturns[i]*dailyReturns[i];
     }
   double mean = sum / validDays;
   double variance = (sumSq / validDays) - (mean*mean);
   if(variance <= 0.0)
      return 0.0;
   double std = MathSqrt(variance);
   if(std == 0.0)
      return 0.0;
   return mean / std * MathSqrt(252);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double Metrics::CalculateProfitFactor(const TradeResult &trades[])
  {
   int n = ArraySize(trades);
   if(n == 0)
      return 0.0;
   double gain = 0.0, loss = 0.0;
   for(int i = 0; i < n; i++)
     {
      if(trades[i].profit > 0)
         gain += trades[i].profit;
      else
         loss -= trades[i].profit;
     }
   if(loss == 0.0)
      return 999.0;
   return gain / loss;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double Metrics::CalculateMaxDrawdown(const TradeResult &trades[])
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
//|                                                                  |
//+------------------------------------------------------------------+
double Metrics::CalculateExpectancy(const TradeResult &trades[])
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
//|                                                                  |
//+------------------------------------------------------------------+
double Metrics::CalculateWinRate(const TradeResult &trades[])
  {
   int n = ArraySize(trades), wins = 0;
   for(int i = 0; i < n; i++)
      if(trades[i].profit > 0)
         wins++;
   return (n > 0) ? (double)wins / n : 0.0;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double Metrics::CalculateSortinoRatio(const TradeResult &trades[], double targetReturn = 0.0)
  {
   int n = ArraySize(trades);
   if(n < 2)
      return 0.0;
   double dailyReturns[];
   int validDays;
   BuildDailyReturns(trades, dailyReturns, validDays);
   if(validDays < 2)
      return 0.0;
   double sum = 0.0;
   int downCount = 0;
   double sumSqDown = 0.0;
   for(int i = 0; i < validDays; i++)
     {
      sum += dailyReturns[i];
      if(dailyReturns[i] < targetReturn)
        {
         double diff = dailyReturns[i] - targetReturn;
         sumSqDown += diff*diff;
         downCount++;
        }
     }
   double mean = sum / validDays;
   if(downCount == 0)
      return (mean > targetReturn) ? 999.0 : 0.0;
   double downsideDev = MathSqrt(sumSqDown / downCount);
   if(downsideDev == 0.0)
      return 0.0;
   return (mean - targetReturn) / downsideDev * MathSqrt(252);
  }

#endif // __METRICS_MQH__
//+------------------------------------------------------------------+
