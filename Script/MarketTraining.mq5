//+------------------------------------------------------------------+
//|                                               MarketTraining.mq5 |
//|                      Arion v1.0 - Script de Recolección 12D      |
//|        (Features oficiales SMC + dirección adaptativa eficiente) |
//|        * CORREGIDO: Promoción a extremos idéntica al EA          |
//|                        Autor: Alexy Hernández                    |
//|                        Versión: 1.0                              |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernández. Todos los derechos reservados."
#property version   "1.0"
#property script_show_inputs

#include "..\\Experts\\Arion\\SmartMoney.mqh"

input int    InpMaxBars    = 0;          // 0 = todas disponibles
input string InpOutputFile = "";         // vacío = nombre automático
input string InpStartDate  = "01/01/2020";

//+------------------------------------------------------------------+
//| Convierte DD/MM/YYYY a datetime                                  |
//+------------------------------------------------------------------+
datetime ConvertDateDDMMYYYY(string dateStr)
  {
   string parts[];
   if(StringSplit(dateStr, '/', parts) != 3)
      return 0;
   int day=(int)StringToInteger(parts[0]), month=(int)StringToInteger(parts[1]), year=(int)StringToInteger(parts[2]);
   if(day<1 || day>31 || month<1 || month>12 || year<2000 || year>3000)
      return 0;
   int maxDays=31;
   if(month==2)
      maxDays=((year%4==0 && year%100!=0) || year%400==0)?29:28;
   else
      if(month==4 || month==6 || month==9 || month==11)
         maxDays=30;
   if(day>maxDays)
      return 0;
   return StringToTime(StringFormat("%04d.%02d.%02d", year, month, day));
  }

//+------------------------------------------------------------------+
//| Dirección basada exclusivamente en ADX, RSI y momentum            |
//| (replica EXACTAMENTE SmartMoney::GetMacroDirection incluyendo     |
//|  la promoción a extremos)                                        |
//+------------------------------------------------------------------+
double GetDirectionFromIndicators(double adx, double rsi, double momentum)
  {
// Fallback sin dirección fractal
   double direction = 0.0;
   if(adx >= 12.0)
     {
      if(rsi > 53.0 && momentum > 0.0)
         direction =  0.5;
      else
         if(rsi < 47.0 && momentum < 0.0)
            direction = -0.5;
         else
            if(rsi > 50.0)
               direction =  0.5;
            else
               if(rsi < 50.0)
                  direction = -0.5;
     }
   if(direction == 0.0)
     {
      if(momentum > 0.02 && rsi > 45.0)
         direction =  0.5;
      else
         if(momentum < -0.02 && rsi < 55.0)
            direction = -0.5;
         else
            if(momentum > 0.05)
               direction =  0.5;
            else
               if(momentum < -0.05)
                  direction = -0.5;
     }

// --- PROMOCIÓN A EXTREMOS (idéntica a SmartMoney::GetMacroDirection) ---
   if(direction == 0.5)
     {
      if((rsi < 35.0 && momentum > 0.15) || (adx > 25.0 && momentum > 0.05) || (momentum > 0.3))
         direction = 1.0;
     }
   else
      if(direction == -0.5)
        {
         if((rsi > 65.0 && momentum < -0.15) || (adx > 25.0 && momentum < -0.05) || (momentum < -0.3))
            direction = -1.0;
        }

// También puede promoverse directamente desde 0 si las condiciones son muy fuertes
   if(direction == 0.0 && adx > 20.0)
     {
      if(rsi > 65.0 && momentum > 0.15)
         direction =  1.0;
      if(rsi < 35.0 && momentum < -0.15)
         direction = -1.0;
     }

   return direction;
  }

//+------------------------------------------------------------------+
//| Script principal                                                  |
//+------------------------------------------------------------------+
void OnStart()
  {
   string symbol = _Symbol;
   ENUM_TIMEFRAMES tf = PERIOD_M15;

   datetime endDate = TimeCurrent();
   datetime startDate = (InpStartDate=="") ? endDate - 5*365*24*60*60 : ConvertDateDDMMYYYY(InpStartDate);
   if(startDate<=0 || startDate>=endDate)
      startDate = endDate - 5*365*24*60*60;

   string outputFile = InpOutputFile;
   if(outputFile=="")
     {
      string s=TimeToString(startDate,TIME_DATE), e=TimeToString(endDate,TIME_DATE);
      StringReplace(s,".","");
      StringReplace(e,".","");
      outputFile = "Arion\\" + symbol + "_" + s + "_" + e + "_KNN.csv";
     }
   if(!FolderCreate("Arion"))
      ResetLastError();

   int handle = FileOpen(outputFile, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(handle==INVALID_HANDLE)
     {
      Print("Error creando ",outputFile);
      return;
     }
   FileWrite(handle,"slope,atr,momentum,volFlow,adx,rsi,deltaVol,spreadDev,smcRatio,relStrength,normVolatility,volRatio,direction,time");

// --- 1. Cargar todas las barras de precios (OHLC + tick volume) ---
   MqlRates rates[];
   int totalBars = CopyRates(symbol, tf, startDate, endDate, rates);
   if(totalBars < 21)
     {
      Print("Pocas barras: ",totalBars);
      FileClose(handle);
      return;
     }
   ArraySetAsSeries(rates, true);            // rates[0] = más reciente

   if(InpMaxBars>0 && totalBars>InpMaxBars)
      totalBars = InpMaxBars;

// --- 2. Copiar buffers de indicadores UNA SOLA VEZ ---
   int atrHandle = iATR(symbol, tf, 14);
   int adxHandle = iADX(symbol, tf, 14);
   int rsiHandle = iRSI(symbol, tf, 14, PRICE_CLOSE);
   if(atrHandle==INVALID_HANDLE || adxHandle==INVALID_HANDLE || rsiHandle==INVALID_HANDLE)
     { Print("Error creando indicadores"); FileClose(handle); return; }

   double atrBuf[], adxBuf[], rsiBuf[];
   int atrCopied = CopyBuffer(atrHandle, 0, 0, totalBars, atrBuf);
   int adxCopied = CopyBuffer(adxHandle, 0, 0, totalBars, adxBuf);
   int rsiCopied = CopyBuffer(rsiHandle, 0, 0, totalBars, rsiBuf);
   IndicatorRelease(atrHandle);
   IndicatorRelease(adxHandle);
   IndicatorRelease(rsiHandle);

   ArraySetAsSeries(atrBuf, true);
   ArraySetAsSeries(adxBuf, true);
   ArraySetAsSeries(rsiBuf, true);

   if(atrCopied < 14 || adxCopied < 14 || rsiCopied < 14)
     { Print("Datos insuficientes en indicadores"); FileClose(handle); return; }

   int atrM1 = iATR(symbol, PERIOD_M1, 14);
   int atrH4 = iATR(symbol, PERIOD_H4, 14);

   int max_i = MathMin(totalBars - 21, MathMin(atrCopied-1, MathMin(adxCopied-1, rsiCopied-1)));
   int min_i = 20;
   if(max_i < min_i)
     {
      Print("Rango insuficiente");
      FileClose(handle);
      return;
     }

   Print("Procesando ", max_i - min_i + 1, " barras...");

   SmartMoney smc(symbol);
   smc.Initialize();
   smc.SetTrainingThresholds(10.0, 15.0, 0.1);

   uint processed = 0, exported = 0;
   int classCount[5] = {0,0,0,0,0};
   uint startTick = GetTickCount();

   for(int i = max_i; i >= min_i; i--)
     {
      if(processed % MathMax(1, (max_i-min_i+1)/100) == 0)
         Print("Progreso: ", DoubleToString((double)processed/(max_i-min_i+1)*100,1), "%");

      datetime barTime = rates[i].time;
      double atr = atrBuf[i];
      if(atr == 0.0)
        {
         processed++;
         continue;
        }
      double adx = adxBuf[i];
      double rsi = rsiBuf[i];

      // Pendiente
      double sumX=0, sumY=0, sumXY=0, sumX2=0;
      for(int k=0; k<20; k++)
        {
         double y = rates[i+1+k].close;
         sumX  += k;
         sumY  += y;
         sumXY += k * y;
         sumX2 += k * k;
        }
      double den = 20.0*sumX2 - sumX*sumX;
      double slope = (MathAbs(den) > 1e-12) ? (20.0*sumXY - sumX*sumY) / den : 0.0;

      double close_i   = rates[i].close;
      double close_past = rates[i+20].close;
      double momentum = (close_i - close_past) / (atr * 20.0 + 0.0001);

      long tickVol_i = rates[i].tick_volume;
      double close_prev = rates[i+1].close;
      double volFlow = (tickVol_i * (close_i - close_prev)) / (atr * close_i + 0.0001);

      // Dirección CORREGIDA con promoción
      double direction = GetDirectionFromIndicators(adx, rsi, momentum);

      // deltaVol
      double avgVol = 0;
      for(int k=0; k<20; k++)
         avgVol += (double)rates[i+1+k].tick_volume;
      avgVol /= 20.0;
      double deltaVol = (avgVol > 0) ? ((double)tickVol_i - avgVol) / avgVol : 0.0;

      // spreadDev
      long spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
      double spreadDev = 0;
      if(spread > 0)
        {
         long avgSp = spread;
         spreadDev = (spread - (double)avgSp) / avgSp;
        }

      // smcRatio
      double smcRatio = smc.GetOBMitigationRatio(close_i, direction > 0.0);

      // relStrength
      int h4Shift = iBarShift(symbol, PERIOD_H4, barTime, false);
      double relStrength = 0;
        {
         double maH4[];
         if(CopyClose(symbol, PERIOD_H4, h4Shift, 1, maH4) == 1)
            relStrength = (close_i - maH4[0]) / (atr + 1e-9);
        }

      double normVolatility = atr / close_i;

      double volRatio = 1.0;
      if(atrM1 != INVALID_HANDLE && atrH4 != INVALID_HANDLE)
        {
         int m1Shift = iBarShift(symbol, PERIOD_M1, barTime, false);
         double m1[], h4[];
         if(CopyBuffer(atrM1, 0, m1Shift, 1, m1)==1 && CopyBuffer(atrH4, 0, h4Shift, 1, h4)==1 && h4[0]!=0.0)
            volRatio = m1[0] / h4[0];
        }

      if(direction == -1.0)
         classCount[0]++;
      else
         if(direction == -0.5)
            classCount[1]++;
         else
            if(direction ==  0.0)
               classCount[2]++;
            else
               if(direction ==  0.5)
                  classCount[3]++;
               else
                  if(direction ==  1.0)
                     classCount[4]++;

      FileWrite(handle, StringFormat("%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.1f,%d",
                                     slope, atr, momentum, volFlow, adx, rsi, deltaVol, spreadDev, smcRatio, relStrength, normVolatility, volRatio,
                                     direction, (long)barTime));
      exported++;
      processed++;
     }

   double elapsed = (GetTickCount() - startTick) / 1000.0;
   FileClose(handle);
   if(atrM1 != INVALID_HANDLE)
      IndicatorRelease(atrM1);
   if(atrH4 != INVALID_HANDLE)
      IndicatorRelease(atrH4);

   Print("✅ Exportación finalizada: ", exported, " muestras (", DoubleToString(elapsed,1), " s)");
   Print("Archivo: ", outputFile);
   Print("Distribución: Strong Sell=", classCount[0], " Sell=", classCount[1], " Neutral=", classCount[2], " Buy=", classCount[3], " Strong Buy=", classCount[4]);
  }
//+------------------------------------------------------------------+
