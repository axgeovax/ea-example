//+------------------------------------------------------------------+
//|                                               MarketTraining.mq5 |
//|                      Arion v1.0 - Script de Recolección 12D      |
//|        Exporta muestras KNN 12D usando SMC Fractal Dinámico      |
//|        Umbrales de promoción adaptativos por volatilidad         |
//|                        Autor: Alexy Hernández                    |
//|                        Versión: 1.0                              |
//|        Copyright (c) 2025 Alexy Hernández. Todos los derechos    |
//|        reservados.                                               |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernández. Todos los derechos reservados."
#property version   "1.0"
#property script_show_inputs

#include "..\Experts\Arion\SmartMoney.mqh"
#include "..\Experts\Arion\KnnClassifier.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                            |
//+------------------------------------------------------------------+
input int    InpMaxBars    = 0;      // 0 = sin límite; >0 limita el número de barras a procesar
input string InpOutputFile = "";     // Nombre del CSV (vacío = nombre automático en Arion/)
input string InpStartDate  = "01/01/2020"; // Fecha inicio (DD/MM/AAAA). Vacío = automático (5 años atrás)

//+------------------------------------------------------------------+
//| Convierte DD/MM/AAAA a datetime                                   |
//+------------------------------------------------------------------+
datetime ConvertDateDDMMYYYY(string dateStr)
  {
   string parts[];
   if(StringSplit(dateStr, '/', parts) != 3)
      return 0;
   int day   = (int)StringToInteger(parts[0]);
   int month = (int)StringToInteger(parts[1]);
   int year  = (int)StringToInteger(parts[2]);
   if(day<1 || day>31 || month<1 || month>12 || year<2000 || year>3000)
      return 0;
   int maxDays = 31;
   if(month==2)
      maxDays = ((year%4==0 && year%100!=0) || year%400==0) ? 29 : 28;
   else
      if(month==4 || month==6 || month==9 || month==11)
         maxDays=30;
   if(day>maxDays)
      return 0;
   string mtDate = StringFormat("%04d.%02d.%02d", year, month, day);
   return StringToTime(mtDate);
  }

//+------------------------------------------------------------------+
//| Script program start function                                     |
//+------------------------------------------------------------------+
void OnStart()
  {
   string symbol = _Symbol;
   ENUM_TIMEFRAMES tf = PERIOD_M15;

// --- Fechas automáticas o personalizadas ---
   datetime endDate   = TimeCurrent();
   datetime startDate;
   if(InpStartDate == "")
      startDate = endDate - 5*365*24*60*60;   // 5 años
   else
     {
      startDate = ConvertDateDDMMYYYY(InpStartDate);
      if(startDate<=0 || startDate>=endDate)
        {
         Print("Fecha inválida, usando 5 años atrás.");
         startDate = endDate - 5*365*24*60*60;
        }
     }

// --- Nombre de archivo de salida ---
   string outputFile = InpOutputFile;
   if(outputFile == "")
     {
      string startStr = TimeToString(startDate, TIME_DATE);
      string endStr   = TimeToString(endDate, TIME_DATE);
      StringReplace(startStr, ".", "");
      StringReplace(endStr, ".", "");
      outputFile = "Arion\\" + symbol + "_" + startStr + "_" + endStr + "_KNN.csv";
     }

// Asegurar carpeta
   if(!FolderCreate("Arion"))
      ResetLastError();

   int handle = FileOpen(outputFile, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
     {
      Print("Error al crear ", outputFile, " error ", GetLastError());
      return;
     }

// --- Cabecera 12D ---
   FileWrite(handle, "slope,atr,momentum,volFlow,adx,rsi,deltaVol,spreadDev,smcRatio,relStrength,normVolatility,volRatio,direction,time");

// --- Inicializar módulos SMC ---
   SmartMoney smc(symbol);
   smc.Initialize();
// Umbrales ultra‑relajados para que SMC produzca más direcciones débiles
   smc.SetTrainingThresholds(10.0, 15.0, 0.1);

// --- Indicadores necesarios ---
   int atrHandle = iATR(symbol, tf, 14);
   int atrM1     = iATR(symbol, PERIOD_M1, 14);
   int atrH4     = iATR(symbol, PERIOD_H4, 14);
   if(atrHandle==INVALID_HANDLE)
     {
      Print("Error al crear iATR M15");
      FileClose(handle);
      return;
     }

// --- Barras disponibles ---
   int totalBars = Bars(symbol, tf, startDate, endDate);
   Print("Barras disponibles: ", totalBars);
   if(totalBars < 21)
     {
      Print("Muy pocas barras (mínimo 21)");
      FileClose(handle);
      return;
     }
   if(InpMaxBars>0 && totalBars > InpMaxBars)
      totalBars = InpMaxBars;

// Calcular ATR promedio de las últimas 100 barras para adaptar umbrales
   double avgATR = 0;
   int countATR = MathMin(100, totalBars-20);
   for(int j=0; j<countATR; j++)
     {
      double buf[1];
      if(CopyBuffer(atrHandle, 0, j, 1, buf) == 1)
         avgATR += buf[0];
     }
   avgATR = (countATR>0) ? avgATR/countATR : 0.001;
   double volFactor = (avgATR > 0) ? MathMax(0.5, MathMin(2.0, 0.001 / avgATR)) : 1.0; // adapta volFlow

// Umbrales de promoción adaptativos
   double rsiLowThreshold  = 40.0 + 10.0 * volFactor;
   double rsiHighThreshold = 60.0 - 10.0 * volFactor;
   double momLowThreshold  = 0.10 * volFactor;
   double momHighThreshold = 0.10 * volFactor;

   Print("Exportando ", symbol, " (", totalBars, " barras, ", TimeToString(startDate), " -> ", TimeToString(endDate), ")");
   Print("ATR promedio: ", DoubleToString(avgATR, 5), " | Factor adaptación: ", DoubleToString(volFactor, 2));

   int processed = 0, exported = 0;
   int promotedToStrong = 0;
   uint startTick = GetTickCount();

// Conteo de clases
   int classCount[5] = {0,0,0,0,0}; // -1, -0.5, 0, 0.5, 1

// --- Bucle principal ---
   for(int i = totalBars-1; i >= 20; i--)
     {
      if(processed % MathMax(1, totalBars/100) == 0)
         Print("Progreso: ", DoubleToString(processed*100.0/totalBars, 0), "%");

      if(i >= Bars(symbol, tf))
         continue;

      datetime barTime = iTime(symbol, tf, i);
      if(barTime == 0)
         continue;

      int h4Shift = iBarShift(symbol, PERIOD_H4, barTime, false);
      int m1Shift = iBarShift(symbol, PERIOD_M1, barTime, false);

      // --- Obtener las 20 barras PREVIAS a i ---
      double close[], open[], high[], low[];
      long volumes[];
      int startCopy = i + 1;
      int countCopy = 20;
      ArrayResize(close, countCopy);
      ArrayResize(open, countCopy);
      ArrayResize(high, countCopy);
      ArrayResize(low, countCopy);
      ArrayResize(volumes, countCopy);
      if(CopyClose(symbol, tf, startCopy, countCopy, close) != countCopy)
         continue;
      if(CopyOpen(symbol, tf, startCopy, countCopy, open) != countCopy)
         continue;
      if(CopyHigh(symbol, tf, startCopy, countCopy, high) != countCopy)
         continue;
      if(CopyLow(symbol, tf, startCopy, countCopy, low) != countCopy)
         continue;
      if(CopyTickVolume(symbol, tf, startCopy, countCopy, volumes) != countCopy)
         continue;

      // Precio y volumen actuales (barra i)
      double currentCloseArr[1];
      if(CopyClose(symbol, tf, i, 1, currentCloseArr) != 1)
         continue;
      double currentClose = currentCloseArr[0];

      long tickVol_i[1];
      if(CopyTickVolume(symbol, tf, i, 1, tickVol_i) != 1)
         continue;

      // --- 1. Slope ---
      double sumX=0, sumY=0, sumXY=0, sumX2=0;
      for(int j=0; j<20; j++)
        {
         double x = j;
         double y = close[j];
         sumX += x;
         sumY += y;
         sumXY += x*y;
         sumX2 += x*x;
        }
      double den = 20*sumX2 - sumX*sumX;
      if(MathAbs(den) < 1e-12)
         continue;
      double slope = (20*sumXY - sumX*sumY) / den;

      // --- 2. ATR ---
      double atrV[1];
      if(CopyBuffer(atrHandle, 0, i, 1, atrV) != 1)
         continue;
      double atr = atrV[0];

      // --- 3. Momentum (normalizado por ATR) ---
      double momentum = (currentClose - close[19]) / (atr * 20 + 0.0001);

      // --- 4. Volume Flow ---
      double volFlow = 0.0;
      for(int j=0; j<20; j++)
        {
         double dirVol = (close[j] > open[j]) ? 1.0 : -1.0;
         volFlow += volumes[j] * dirVol;
        }

      // --- Dirección SMC ---
      smc.UpdateStructure(i);
      double adx = smc.GetADX(i);
      double rsi = smc.GetRSI(i);
      double direction = smc.GetMacroDirection(i);

      // --- Fallback si SMC no detectó nada ---
      if(direction == 0.0)
        {
         if(rsi < rsiLowThreshold && momentum > momLowThreshold)
            direction = 0.5;
         else
            if(rsi > rsiHighThreshold && momentum < -momLowThreshold)
               direction = -0.5;
            else
               if(rsi < 30.0 && momentum > 0.2)
                  direction = 1.0;
               else
                  if(rsi > 70.0 && momentum < -0.2)
                     direction = -1.0;
        }

      // === PROMOCIÓN DE EXTREMOS (adaptativa) ===
      if(direction == 0.5)
        {
         if((rsi < 35.0 && momentum > 0.15) ||    // condiciones originales
            (adx > 25.0 && momentum > 0.05))      // promoción por ADX fuerte
           {
            direction = 1.0;
            promotedToStrong++;
           }
        }
      else
         if(direction == -0.5)
           {
            if((rsi > 65.0 && momentum < -0.15) ||
               (adx > 25.0 && momentum < -0.05))
              {
               direction = -1.0;
               promotedToStrong++;
              }
           }

      // --- Filtro de calidad: solo descartamos direcciones neutras ---
      if(direction == 0.0)
         continue;
      // (Eliminado el filtro de volFlow para no descartar extremos promocionados)

      // --- 7. deltaVol ---
      double deltaVol = 0.0;
        {
         double avgVol = 0;
         for(int k=0; k<20; k++)
            avgVol += (double)volumes[k];
         avgVol /= 20;
         if(avgVol > 0)
            deltaVol = ((double)tickVol_i[0] - avgVol) / avgVol;
        }

      // --- 8. spreadDev ---
      double spreadDev = 0.0;
        {
         long spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
         double avgSp = 0;
         for(int k=0; k<20; k++)
            avgSp += (double)spread;
         avgSp /= 20;
         if(avgSp > 0)
            spreadDev = ((double)spread - avgSp) / avgSp;
        }

      // --- 9. smcRatio ---
      double smcRatio = smc.GetOBMitigationRatio(currentClose, direction > 0);

      // --- 10. relStrength ---
      double relStrength = 0.0;
        {
         double maH4[];
         if(CopyClose(symbol, PERIOD_H4, h4Shift, 1, maH4) == 1)
            relStrength = (currentClose - maH4[0]) / (atr + 1e-9);
        }

      // --- 11. normVolatility ---
      double normVolatility = atr / currentClose;

      // --- 12. volRatio ---
      double volRatio = 1.0;
      if(atrM1 != INVALID_HANDLE && atrH4 != INVALID_HANDLE)
        {
         double m1[1], h4[1];
         if(CopyBuffer(atrM1, 0, m1Shift, 1, m1)==1 && CopyBuffer(atrH4, 0, h4Shift, 1, h4)==1 && h4[0]!=0.0)
            volRatio = m1[0] / h4[0];
        }

      // Contabilizar clase
      if(direction == -1.0)
         classCount[0]++;
      else
         if(direction == -0.5)
            classCount[1]++;
         else
            if(direction == 0.5)
               classCount[3]++;
            else
               if(direction == 1.0)
                  classCount[4]++;

      // Escribir línea CSV
      string line = StringFormat("%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.1f,%d",
                                 slope, atr, momentum, volFlow, adx, rsi,
                                 deltaVol, spreadDev, smcRatio, relStrength, normVolatility, volRatio,
                                 direction, (long)barTime);
      FileWrite(handle, line);
      exported++;
      processed++;
     }

// --- Finalización ---
   double elapsed = (GetTickCount() - startTick)/1000.0;
   FileClose(handle);
   IndicatorRelease(atrHandle);
   if(atrM1 != INVALID_HANDLE)
      IndicatorRelease(atrM1);
   if(atrH4 != INVALID_HANDLE)
      IndicatorRelease(atrH4);

   Print("✅ Exportación finalizada: ", exported, " muestras (", DoubleToString(elapsed,1), " s)");
   Print("Archivo: ", outputFile);
   if(FileIsExist(outputFile))
      Print("✔ Archivo creado correctamente.");
   else
      Print("❌ ERROR: No se pudo crear el archivo.");

   Print("Muestras promocionadas a Strong: ", promotedToStrong);

   Print("Distribución de clases recolectadas:");
   Print("   Strong Sell (-1.0): ", classCount[0]);
   Print("   Sell       (-0.5): ", classCount[1]);
   Print("   Neutral    ( 0.0): 0 (filtradas)");
   Print("   Buy         (0.5): ", classCount[3]);
   Print("   Strong Buy  (1.0): ", classCount[4]);

   bool missing = false;
   if(classCount[0]==0)
     {
      Print("⚠ Faltan muestras Strong Sell");
      missing=true;
     }
   if(classCount[1]==0)
     {
      Print("⚠ Faltan muestras Sell");
      missing=true;
     }
   if(classCount[3]==0)
     {
      Print("⚠ Faltan muestras Buy");
      missing=true;
     }
   if(classCount[4]==0)
     {
      Print("⚠ Faltan muestras Strong Buy");
      missing=true;
     }

   if(missing)
      Print("→ Para obtener más variedad, amplíe el rango de fechas o ajuste los umbrales en SetTrainingThresholds()");
   else
      Print("✔ Todas las clases necesarias están presentes. CSV listo para entrenamiento.");
  }
//+------------------------------------------------------------------+
