//+------------------------------------------------------------------+
//|                                                 SmartMoney.mqh   |
//|                        Arion - SMC Fractal Dinamico v2.0        |
//|        * GetMacroDirection sin promoción a extremos              |
//|        * Incluye TrainingLabelGenerator para etiquetas reales    |
//|                        Autor: Alexy Hernandez                    |
//|                        Version: 2.0                              |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernandez. Todos los derechos reservados."
#property link      "https://github.com/axgeovax"
#property version   "2.0"
#property strict

#ifndef __SMARTMONEY_MQH__
#define __SMARTMONEY_MQH__

#include "TrainingLabelGenerator.mqh"

//+------------------------------------------------------------------+
//| Estructuras                                                      |
//+------------------------------------------------------------------+
struct OrderBlock
  {
   datetime          time;
   double            high, low;
   double            open, close;
   bool              bullish;
   bool              mitigated;
   int               scale;           // 0 = menor, 1 = intermedio, 2 = mayor
   double            volumeFlow;
   double            relevance;       // 0-100
   bool              refined;         // zona anidada de alta probabilidad
  };

struct FairValueGap
  {
   datetime          time;
   double            gapHigh, gapLow;
   bool              bullish;
   bool              mitigated;
   int               scale;
   double            volumeFlow;
   double            relevance;
   bool              refined;
  };

struct LiquidityPool
  {
   double            priceLevel;
   bool              bullish;         // true = resistencia, false = soporte
   int               zoneCount;
   double            totalVolume;
   double            strength;        // 0-1
  };


//+------------------------------------------------------------------+
//| Clase SmartMoney – SMC Fractal Dinamico                          |
//+------------------------------------------------------------------+
class SmartMoney
  {
private:
   string            m_symbol;
   double            m_atrBase;
   double            m_atrMultiplier;
   int               m_maxSlots;
   int               m_maxPoolSlots;

   // Factores ajustables para deteccion de OB y FVG
   double            m_obBodyFactor;
   double            m_fvgGapFactor;

   OrderBlock        m_orderBlocks[];
   int               m_totalOB;
   FairValueGap      m_fairValueGaps[];
   int               m_totalFVG;

   LiquidityPool     m_liquidityPools[];
   int               m_totalPools;

   double            m_macroDirection;    // -0.5, 0, 0.5  (sin extremos)
   double            m_macroStrength;

   int               m_handleATR;
   int               m_handleATR_H1;      // ATR en H1 para adaptacion
   int               m_handleADX;
   int               m_handleRSI;
   bool              m_indicatorsReady;

   // Umbrales ajustables
   double            m_adxWeak;
   double            m_adxStrong;
   double            m_momStrong;

   // Cache para Choppiness Index
   datetime          m_lastChopCalcTime;
   double            m_lastChopValue;
   static const int         CHOP_CACHE_SECONDS;  // Cache por 60 segundos

   // --- Metodos internos ---
   void              EnsureIndicators();
   bool              DetectFractalStructure(int start_bar = 0);
   double            CalculateRelevance(datetime zoneTime, double volumeFlow, int scale, datetime referenceTime);
   void              PruneLowRelevanceZones();
   void              DetectNestedZones();              // optimizada
   void              UpdateMitigationState(int start_bar = 0);  // usa cierre de vela penetradora
   void              BuildLiquidityPools();
   void              AddToPool(double price, bool bullish, double volume);

   // ATR multiplier adaptativo
   double            GetATRMultiplierAdaptive();

   // Confluencia con H1/H4
   bool              CheckHigherTimeframeConfluence(bool bullishZone);
   double            GetMacroDirectionForTimeframe(ENUM_TIMEFRAMES tf, int start_bar);

public:
                     SmartMoney(string symbol = NULL);
                    ~SmartMoney() { Cleanup(); }

   bool              Initialize();

   void              UpdateStructure(bool newMacro, bool newZona);
   void              UpdateStructure(int start_bar = 0);

   void              Cleanup();

   // Devuelve dirección macro filtrada: solo -0.5, 0, 0.5
   double            GetMacroDirection(int start_bar = 0);

   bool              IsOBMitigated(double price, bool buyDirection) const;
   bool              IsFVGMitigated(double price, bool buyDirection) const;
   double            GetOBMitigationRatio(double price, bool buyDirection) const;

   double            CalculateChoppinessIndex(int periods = 14);
   bool              ValidateChoppinessFilter(int periods = 14);

   double            CalculateRegressionSlope(int lookback = 20, ENUM_TIMEFRAMES tf = PERIOD_M1);
   double            GetATR(int period = 14, int start_bar = 0);
   double            GetADX(int start_bar = 0);
   double            GetRSI(int start_bar = 0);
   double            CalculateMomentum(int lookback = 20, ENUM_TIMEFRAMES tf = PERIOD_M15, int start_bar = 0);
   double            CalculateVolumeFlow(int lookback = 20, ENUM_TIMEFRAMES tf = PERIOD_M15, int start_bar = 0);

   double            FindOppositeLiquidity(double currentPrice, bool buyDirection);

   int               GetActiveOrderBlocks() const;
   int               GetActiveFairValueGaps() const;
   int               GetRefinedZoneCount() const;

   bool              SaveState(string fileName);
   bool              LoadState(string fileName);

   void              SetTrainingThresholds(double adxWeak, double adxStrong, double momStrong);
   void              SetDetectionFactors(double obBodyFactor, double fvgGapFactor);
  };

//+------------------------------------------------------------------+
//| Constructor                                                        |
//+------------------------------------------------------------------+
SmartMoney::SmartMoney(string symbol)
  {
   m_symbol = (symbol == NULL) ? _Symbol : symbol;
   m_atrBase = 0.0;
   m_atrMultiplier = 1.5;
   m_maxSlots = 100;
   m_maxPoolSlots = 20;
   m_totalOB = 0;
   m_totalFVG = 0;
   m_totalPools = 0;
   m_macroDirection = 0;
   m_macroStrength = 0.0;
   m_handleATR = INVALID_HANDLE;
   m_handleATR_H1 = INVALID_HANDLE;
   m_handleADX = INVALID_HANDLE;
   m_handleRSI = INVALID_HANDLE;
   m_indicatorsReady = false;

   m_adxWeak   = 25.0;
   m_adxStrong = 40.0;
   m_momStrong = 1.0;

// Factores de deteccion por defecto
   m_obBodyFactor = 0.5;
   m_fvgGapFactor = 0.2;

   m_lastChopCalcTime = 0;
   m_lastChopValue = -1.0;

   ArrayResize(m_orderBlocks, 0);
   ArrayResize(m_fairValueGaps, 0);
   ArrayResize(m_liquidityPools, 0);
  }

//+------------------------------------------------------------------+
//| Inicializa los handles de indicadores si aun no estan creados    |
//+------------------------------------------------------------------+
void SmartMoney::EnsureIndicators()
  {
   if(m_indicatorsReady)
      return;

   if(m_handleATR == INVALID_HANDLE)
      m_handleATR = iATR(m_symbol, PERIOD_M15, 14);
   if(m_handleATR_H1 == INVALID_HANDLE)
      m_handleATR_H1 = iATR(m_symbol, PERIOD_H1, 14);
   if(m_handleADX == INVALID_HANDLE)
      m_handleADX = iADX(m_symbol, PERIOD_M15, 14);
   if(m_handleRSI == INVALID_HANDLE)
      m_handleRSI = iRSI(m_symbol, PERIOD_M15, 14, PRICE_CLOSE);

   m_indicatorsReady = (m_handleATR != INVALID_HANDLE &&
                        m_handleATR_H1 != INVALID_HANDLE &&
                        m_handleADX != INVALID_HANDLE &&
                        m_handleRSI != INVALID_HANDLE);
  }

//+------------------------------------------------------------------+
//| ATR multiplier adaptativo                                         |
//+------------------------------------------------------------------+
double SmartMoney::GetATRMultiplierAdaptive()
  {
   double atrM15[1], atrH1[1];
   if(m_handleATR == INVALID_HANDLE || m_handleATR_H1 == INVALID_HANDLE)
      return 1.5;

   if(CopyBuffer(m_handleATR, 0, 0, 1, atrM15) != 1 ||
      CopyBuffer(m_handleATR_H1, 0, 0, 1, atrH1) != 1)
      return 1.5;

   if(atrH1[0] == 0.0)
      return 1.5;
   double ratio = atrM15[0] / atrH1[0];

   if(ratio < 0.7)
      return 1.2;
   if(ratio > 1.5)
      return 2.0;
   return 1.5;
  }

//+------------------------------------------------------------------+
//| Confluencia con timeframes superiores (H1 y H4)                  |
//+------------------------------------------------------------------+
bool SmartMoney::CheckHigherTimeframeConfluence(bool bullishZone)
  {
   double dirH1 = GetMacroDirectionForTimeframe(PERIOD_H1, 0);
   double dirH4 = GetMacroDirectionForTimeframe(PERIOD_H4, 0);

   if(bullishZone)
      return (dirH1 > 0 && dirH4 > 0);
   else
      return (dirH1 < 0 && dirH4 < 0);
  }

//+------------------------------------------------------------------+
//| Obtener direccion macro para un timeframe dado                    |
//+------------------------------------------------------------------+
double SmartMoney::GetMacroDirectionForTimeframe(ENUM_TIMEFRAMES tf, int start_bar)
  {
   double adxBuf[1], rsiBuf[1];
   int adxHandle = iADX(m_symbol, tf, 14);
   int rsiHandle = iRSI(m_symbol, tf, 14, PRICE_CLOSE);
   if(adxHandle == INVALID_HANDLE || rsiHandle == INVALID_HANDLE)
      return 50.0;

   double adx = (CopyBuffer(adxHandle, 0, start_bar, 1, adxBuf) == 1) ? adxBuf[0] : 0.0;
   double rsi = (CopyBuffer(rsiHandle, 0, start_bar, 1, rsiBuf) == 1) ? rsiBuf[0] : 50.0;
   IndicatorRelease(adxHandle);
   IndicatorRelease(rsiHandle);

   if(adx < m_adxWeak)
      return 50.0;
   if(adx >= m_adxStrong)
     {
      if(rsi > 60.0)
         return 1.0;
      if(rsi < 40.0)
         return -1.0;
      return (rsi > 50.0) ? 0.5 : -0.5;
     }
   return 0.0;
  }

//+------------------------------------------------------------------+
//| Inicializa el modulo SMC                                         |
//+------------------------------------------------------------------+
bool SmartMoney::Initialize()
  {
   if(!SymbolSelect(m_symbol, true))
     {
      Print("Error [SmartMoney]: Symbol ", m_symbol, " not available.");
      return false;
     }
   EnsureIndicators();
   if(!m_indicatorsReady)
     {
      Print("Error [SmartMoney]: Could not create indicators.");
      return false;
     }
   UpdateStructure();  // usa start_bar = 0
   return true;
  }

//+------------------------------------------------------------------+
//| Libera los handles de indicadores                                |
//+------------------------------------------------------------------+
void SmartMoney::Cleanup()
  {
   if(m_handleATR != INVALID_HANDLE)
      IndicatorRelease(m_handleATR);
   if(m_handleATR_H1 != INVALID_HANDLE)
      IndicatorRelease(m_handleATR_H1);
   if(m_handleADX != INVALID_HANDLE)
      IndicatorRelease(m_handleADX);
   if(m_handleRSI != INVALID_HANDLE)
      IndicatorRelease(m_handleRSI);
   m_indicatorsReady = false;
  }

//+------------------------------------------------------------------+
//| Actualizar estructura (compatibilidad)                            |
//+------------------------------------------------------------------+
void SmartMoney::UpdateStructure(bool newMacro, bool newZona)
  {
   UpdateStructure(0);
  }

//+------------------------------------------------------------------+
//| Actualiza la estructura fractal                                  |
//+------------------------------------------------------------------+
void SmartMoney::UpdateStructure(int start_bar = 0)
  {
   DetectFractalStructure(start_bar);
  }

//+------------------------------------------------------------------+
//| Deteccion fractal agnostica al tiempo (con confluencia HTF)      |
//+------------------------------------------------------------------+
bool SmartMoney::DetectFractalStructure(int start_bar = 0)
  {
   EnsureIndicators();
   if(!m_indicatorsReady)
      return false;

// Actualizar multiplicador adaptativo
   m_atrMultiplier = GetATRMultiplierAdaptive();

   double atrBuf[1];
   if(CopyBuffer(m_handleATR, 0, start_bar, 1, atrBuf) != 1)
      return false;
   m_atrBase = atrBuf[0];
   if(m_atrBase <= 0)
      return false;

   MqlRates rates[];
   int barsToCopy = MathMin(100, 1000);
   int copied = CopyRates(m_symbol, PERIOD_CURRENT, start_bar, barsToCopy, rates);
   if(copied <= 20)
      return false;
   ArraySetAsSeries(rates, true);

   if(ArraySize(rates) < copied)
      copied = ArraySize(rates);
   if(copied < 21)
      return false;

   datetime referenceTime = rates[0].time;

   double swingThreshold = m_atrBase * m_atrMultiplier;
   int lastSwingHigh = -1, lastSwingLow = -1;
   double lastHighPrice = 0, lastLowPrice = 0;

   m_totalOB = 0;
   m_totalFVG = 0;
   ArrayResize(m_orderBlocks, 0);
   ArrayResize(m_fairValueGaps, 0);

   int limit = copied - 3;
   for(int i = 5; i < limit; i++)
     {
      if(i+2 >= copied || i-2 < 0)
         continue;

      // --- Swing High ---
      bool isSwingHigh = (rates[i].high > rates[i+1].high && rates[i].high > rates[i+2].high &&
                          rates[i].high > rates[i-1].high && rates[i].high > rates[i-2].high);
      if(isSwingHigh)
        {
         if(lastSwingHigh == -1 || MathAbs(rates[i].high - lastHighPrice) > swingThreshold)
           {
            if(lastLowPrice > 0 && rates[i].high > lastHighPrice * (1 + swingThreshold / rates[i].high))
               m_macroDirection = 1;
            lastSwingHigh = i;
            lastHighPrice = rates[i].high;
           }
        }

      // --- Swing Low ---
      bool isSwingLow = (rates[i].low < rates[i+1].low && rates[i].low < rates[i+2].low &&
                         rates[i].low < rates[i-1].low && rates[i].low < rates[i-2].low);
      if(isSwingLow)
        {
         if(lastSwingLow == -1 || MathAbs(rates[i].low - lastLowPrice) > swingThreshold)
           {
            if(lastHighPrice > 0 && rates[i].low < lastLowPrice * (1 - swingThreshold / rates[i].low))
               m_macroDirection = -1;
            lastSwingLow = i;
            lastLowPrice = rates[i].low;
           }
        }

      // --- Order Blocks (umbral configurable) ---
      if(i >= 1 && i < copied - 1)
        {
         if(rates[i].close < rates[i].open && rates[i-1].close > rates[i-1].open)
           {
            double body = MathAbs(rates[i].close - rates[i].open);
            if(body > m_atrBase * m_obBodyFactor)
              {
               double volFlow = CalculateVolumeFlow(20, PERIOD_CURRENT, start_bar + i);
               ArrayResize(m_orderBlocks, m_totalOB + 1);
               m_orderBlocks[m_totalOB].time = rates[i].time;
               m_orderBlocks[m_totalOB].high = rates[i].high;
               m_orderBlocks[m_totalOB].low = rates[i].low;
               m_orderBlocks[m_totalOB].open = rates[i].open;
               m_orderBlocks[m_totalOB].close = rates[i].close;
               m_orderBlocks[m_totalOB].bullish = false;
               m_orderBlocks[m_totalOB].mitigated = false;
               m_orderBlocks[m_totalOB].scale = (body > m_atrBase * 1.5) ? 2 : (body > m_atrBase * 0.8) ? 1 : 0;
               m_orderBlocks[m_totalOB].volumeFlow = volFlow;
               m_orderBlocks[m_totalOB].refined = false;
               m_totalOB++;
              }
           }
         else
            if(rates[i].close > rates[i].open && rates[i-1].close < rates[i-1].open)
              {
               double body = MathAbs(rates[i].close - rates[i].open);
               if(body > m_atrBase * m_obBodyFactor)
                 {
                  double volFlow = CalculateVolumeFlow(20, PERIOD_CURRENT, start_bar + i);
                  ArrayResize(m_orderBlocks, m_totalOB + 1);
                  m_orderBlocks[m_totalOB].time = rates[i].time;
                  m_orderBlocks[m_totalOB].high = rates[i].high;
                  m_orderBlocks[m_totalOB].low = rates[i].low;
                  m_orderBlocks[m_totalOB].open = rates[i].open;
                  m_orderBlocks[m_totalOB].close = rates[i].close;
                  m_orderBlocks[m_totalOB].bullish = true;
                  m_orderBlocks[m_totalOB].mitigated = false;
                  m_orderBlocks[m_totalOB].scale = (body > m_atrBase * 1.5) ? 2 : (body > m_atrBase * 0.8) ? 1 : 0;
                  m_orderBlocks[m_totalOB].volumeFlow = volFlow;
                  m_orderBlocks[m_totalOB].refined = false;
                  m_totalOB++;
                 }
              }

         // --- Fair Value Gaps (umbral configurable) ---
         if(i+2 < copied)
           {
            if(rates[i].low > rates[i+2].high)
              {
               double gapHigh = rates[i].low;
               double gapLow = rates[i+2].high;
               double gapSize = gapHigh - gapLow;
               if(gapSize > m_atrBase * m_fvgGapFactor)
                 {
                  ArrayResize(m_fairValueGaps, m_totalFVG + 1);
                  m_fairValueGaps[m_totalFVG].time = rates[i].time;
                  m_fairValueGaps[m_totalFVG].gapHigh = gapHigh;
                  m_fairValueGaps[m_totalFVG].gapLow = gapLow;
                  m_fairValueGaps[m_totalFVG].bullish = true;
                  m_fairValueGaps[m_totalFVG].mitigated = false;
                  m_fairValueGaps[m_totalFVG].scale = (gapSize > m_atrBase * 0.5) ? 1 : 0;
                  m_fairValueGaps[m_totalFVG].volumeFlow = CalculateVolumeFlow(20, PERIOD_CURRENT, start_bar + i);
                  m_fairValueGaps[m_totalFVG].refined = false;
                  m_totalFVG++;
                 }
              }
            else
               if(rates[i].high < rates[i+2].low)
                 {
                  double gapHigh = rates[i+2].low;
                  double gapLow = rates[i].high;
                  double gapSize = gapHigh - gapLow;
                  if(gapSize > m_atrBase * m_fvgGapFactor)
                    {
                     ArrayResize(m_fairValueGaps, m_totalFVG + 1);
                     m_fairValueGaps[m_totalFVG].time = rates[i].time;
                     m_fairValueGaps[m_totalFVG].gapHigh = gapHigh;
                     m_fairValueGaps[m_totalFVG].gapLow = gapLow;
                     m_fairValueGaps[m_totalFVG].bullish = false;
                     m_fairValueGaps[m_totalFVG].mitigated = false;
                     m_fairValueGaps[m_totalFVG].scale = (gapSize > m_atrBase * 0.5) ? 1 : 0;
                     m_fairValueGaps[m_totalFVG].volumeFlow = CalculateVolumeFlow(20, PERIOD_CURRENT, start_bar + i);
                     m_fairValueGaps[m_totalFVG].refined = false;
                     m_totalFVG++;
                    }
                 }
           }
        }
     }

// Inyectar fallback si no hay tendencia macro clara
   if(m_macroDirection == 0.0 || (lastSwingHigh == -1 && lastSwingLow == -1))
     {
      double adx = GetADX(start_bar);
      double rsi = GetRSI(start_bar);
      if(adx < m_adxWeak)
         m_macroDirection = 0.0;
      else
         if(rsi > 55.0)
            m_macroDirection = 0.5;
         else
            if(rsi < 45.0)
               m_macroDirection = -0.5;
            else
               m_macroDirection = 0.0;
     }

// Calculo de relevancia con confluencia H1/H4
   for(int i = 0; i < m_totalOB; i++)
     {
      m_orderBlocks[i].relevance = CalculateRelevance(m_orderBlocks[i].time, m_orderBlocks[i].volumeFlow, m_orderBlocks[i].scale, referenceTime);
      if(!CheckHigherTimeframeConfluence(m_orderBlocks[i].bullish))
         m_orderBlocks[i].relevance *= 0.7;
     }
   for(int i = 0; i < m_totalFVG; i++)
     {
      m_fairValueGaps[i].relevance = CalculateRelevance(m_fairValueGaps[i].time, m_fairValueGaps[i].volumeFlow, m_fairValueGaps[i].scale, referenceTime);
      if(!CheckHigherTimeframeConfluence(m_fairValueGaps[i].bullish))
         m_fairValueGaps[i].relevance *= 0.7;
     }

   PruneLowRelevanceZones();
   DetectNestedZones();
   UpdateMitigationState(start_bar);
   BuildLiquidityPools();

   return true;
  }

//+------------------------------------------------------------------+
//| Calcula la relevancia de una zona (0-100)                         |
//+------------------------------------------------------------------+
double SmartMoney::CalculateRelevance(datetime zoneTime, double volumeFlow, int scale, datetime referenceTime)
  {
   double ageHours = (double)(referenceTime - zoneTime) / 3600.0;
   double ageScore = MathMax(0.0, 100.0 - ageHours * 1.5);
   double scaleScore = (scale == 2) ? 100.0 : (scale == 1) ? 70.0 : 40.0;
   double volScore = MathMin(100.0, MathAbs(volumeFlow) / (m_atrBase + 1e-9) * 30.0);
   return ageScore * 0.4 + scaleScore * 0.35 + volScore * 0.25;
  }

//+------------------------------------------------------------------+
//| Elimina las zonas de menor relevancia (PODA O(1))                |
//+------------------------------------------------------------------+
void SmartMoney::PruneLowRelevanceZones()
  {
   if(m_maxSlots <= 0)
      return;

// Order Blocks: sustituir el peor por el ultimo y redimensionar
   while(m_totalOB > m_maxSlots)
     {
      int worstIdx = 0;
      double worstRel = 999.0;
      for(int i = 0; i < m_totalOB; i++)
         if(m_orderBlocks[i].relevance < worstRel)
           {
            worstRel = m_orderBlocks[i].relevance;
            worstIdx = i;
           }
      // Mover el último a la posición del peor y reducir tamaño
      m_orderBlocks[worstIdx] = m_orderBlocks[m_totalOB - 1];
      m_totalOB--;
      ArrayResize(m_orderBlocks, m_totalOB);
     }

// Fair Value Gaps: mismo procedimiento
   while(m_totalFVG > m_maxSlots)
     {
      int worstIdx = 0;
      double worstRel = 999.0;
      for(int i = 0; i < m_totalFVG; i++)
         if(m_fairValueGaps[i].relevance < worstRel)
           {
            worstRel = m_fairValueGaps[i].relevance;
            worstIdx = i;
           }
      m_fairValueGaps[worstIdx] = m_fairValueGaps[m_totalFVG - 1];
      m_totalFVG--;
      ArrayResize(m_fairValueGaps, m_totalFVG);
     }
  }

//+------------------------------------------------------------------+
//| Detectar zonas anidadas                                          |
//+------------------------------------------------------------------+
void SmartMoney::DetectNestedZones()
  {
// --- Order Blocks ---
   if(m_totalOB > 1)
     {
      for(int i = 0; i < m_totalOB-1; i++)
         for(int j = i+1; j < m_totalOB; j++)
            if((m_orderBlocks[i].high - m_orderBlocks[i].low) < (m_orderBlocks[j].high - m_orderBlocks[j].low))
              {
               OrderBlock tmp = m_orderBlocks[i];
               m_orderBlocks[i] = m_orderBlocks[j];
               m_orderBlocks[j] = tmp;
              }

      for(int i = 0; i < m_totalOB-1; i++)
        {
         if(m_orderBlocks[i].mitigated)
            continue;
         for(int j = i+1; j < m_totalOB; j++)
           {
            if(m_orderBlocks[j].mitigated)
               continue;
            if(m_orderBlocks[i].high >= m_orderBlocks[j].high &&
               m_orderBlocks[i].low <= m_orderBlocks[j].low &&
               m_orderBlocks[i].bullish == m_orderBlocks[j].bullish)
              {
               m_orderBlocks[j].refined = true;
              }
           }
        }
     }

// --- Fair Value Gaps ---
   if(m_totalFVG > 1)
     {
      for(int i = 0; i < m_totalFVG-1; i++)
         for(int j = i+1; j < m_totalFVG; j++)
            if((m_fairValueGaps[i].gapHigh - m_fairValueGaps[i].gapLow) < (m_fairValueGaps[j].gapHigh - m_fairValueGaps[j].gapLow))
              {
               FairValueGap tmp = m_fairValueGaps[i];
               m_fairValueGaps[i] = m_fairValueGaps[j];
               m_fairValueGaps[j] = tmp;
              }
      for(int i = 0; i < m_totalFVG-1; i++)
        {
         if(m_fairValueGaps[i].mitigated)
            continue;
         for(int j = i+1; j < m_totalFVG; j++)
           {
            if(m_fairValueGaps[j].mitigated)
               continue;
            if(m_fairValueGaps[i].gapHigh >= m_fairValueGaps[j].gapHigh &&
               m_fairValueGaps[i].gapLow <= m_fairValueGaps[j].gapLow &&
               m_fairValueGaps[i].bullish == m_fairValueGaps[j].bullish)
              {
               m_fairValueGaps[j].refined = true;
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Actualizar mitigacion solo con el cierre                         |
//+------------------------------------------------------------------+
void SmartMoney::UpdateMitigationState(int start_bar = 0)
  {
   MqlRates rates[];
   int barsToCopy = MathMin(50, 1000);
   int copied = CopyRates(m_symbol, PERIOD_CURRENT, start_bar, barsToCopy, rates);
   if(copied < 2)
      return;
   ArraySetAsSeries(rates, true);

   for(int i = 0; i < copied; i++)
     {
      double close = rates[i].close;
      for(int j = 0; j < m_totalOB; j++)
        {
         if(!m_orderBlocks[j].mitigated)
           {
            if(m_orderBlocks[j].bullish && close < m_orderBlocks[j].low)
               m_orderBlocks[j].mitigated = true;
            else
               if(!m_orderBlocks[j].bullish && close > m_orderBlocks[j].high)
                  m_orderBlocks[j].mitigated = true;
           }
        }
      for(int j = 0; j < m_totalFVG; j++)
        {
         if(!m_fairValueGaps[j].mitigated)
           {
            if(m_fairValueGaps[j].bullish && close < m_fairValueGaps[j].gapLow)
               m_fairValueGaps[j].mitigated = true;
            else
               if(!m_fairValueGaps[j].bullish && close > m_fairValueGaps[j].gapHigh)
                  m_fairValueGaps[j].mitigated = true;
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Construye los pools de liquidez (fuerza normalizada internamente)|
//+------------------------------------------------------------------+
void SmartMoney::BuildLiquidityPools()
  {
   ArrayResize(m_liquidityPools, 0);
   m_totalPools = 0;

   for(int i = 0; i < m_totalOB; i++)
     {
      if(!m_orderBlocks[i].mitigated)
        {
         double price = m_orderBlocks[i].bullish ? m_orderBlocks[i].low : m_orderBlocks[i].high;
         AddToPool(price, m_orderBlocks[i].bullish, m_orderBlocks[i].volumeFlow);
        }
     }
   for(int i = 0; i < m_totalFVG; i++)
     {
      if(!m_fairValueGaps[i].mitigated)
        {
         double price = m_fairValueGaps[i].bullish ? m_fairValueGaps[i].gapLow : m_fairValueGaps[i].gapHigh;
         AddToPool(price, m_fairValueGaps[i].bullish, m_fairValueGaps[i].volumeFlow);
        }
     }

   if(m_totalPools == 0)
      return;

// Calcular maximo de zonas y maximo volumen para normalizacion interna
   int maxZones = 0;
   double maxVolume = 0.0;
   for(int i = 0; i < m_totalPools; i++)
     {
      if(m_liquidityPools[i].zoneCount > maxZones)
         maxZones = m_liquidityPools[i].zoneCount;
      if(m_liquidityPools[i].totalVolume > maxVolume)
         maxVolume = m_liquidityPools[i].totalVolume;
     }

   for(int i = 0; i < m_totalPools; i++)
     {
      double zoneRatio = (maxZones > 0) ? (double)m_liquidityPools[i].zoneCount / maxZones : 0.0;
      double volRatio  = (maxVolume > 0) ? m_liquidityPools[i].totalVolume / maxVolume : 0.0;
      m_liquidityPools[i].strength = zoneRatio * 0.6 + volRatio * 0.4;
     }
  }

//+------------------------------------------------------------------+
//| Agrega un nivel de precio al pool (media ponderada por volumen)  |
//+------------------------------------------------------------------+
void SmartMoney::AddToPool(double price, bool bullish, double volume)
  {
   double tolerance = m_atrBase * 0.3;
   for(int i = 0; i < m_totalPools; i++)
     {
      if(m_liquidityPools[i].bullish == bullish &&
         MathAbs(m_liquidityPools[i].priceLevel - price) < tolerance)
        {
         double newTotalVolume = m_liquidityPools[i].totalVolume + volume;
         if(newTotalVolume > 0)
            m_liquidityPools[i].priceLevel = (m_liquidityPools[i].priceLevel * m_liquidityPools[i].totalVolume + price * volume) / newTotalVolume;
         m_liquidityPools[i].zoneCount++;
         m_liquidityPools[i].totalVolume = newTotalVolume;
         return;
        }
     }
   if(m_totalPools < m_maxPoolSlots)
     {
      ArrayResize(m_liquidityPools, m_totalPools + 1);
      m_liquidityPools[m_totalPools].priceLevel = price;
      m_liquidityPools[m_totalPools].bullish = bullish;
      m_liquidityPools[m_totalPools].zoneCount = 1;
      m_liquidityPools[m_totalPools].totalVolume = volume;
      m_liquidityPools[m_totalPools].strength = 0.0;
      m_totalPools++;
     }
  }

//+------------------------------------------------------------------+
//| Busca liquidez opuesta                                           |
//+------------------------------------------------------------------+
double SmartMoney::FindOppositeLiquidity(double currentPrice, bool buyDirection)
  {
   BuildLiquidityPools();
   double bestPrice = 0.0;
   double bestStrength = -1.0;
   for(int i = 0; i < m_totalPools; i++)
     {
      if(buyDirection && !m_liquidityPools[i].bullish && m_liquidityPools[i].priceLevel > currentPrice)
        {
         if(m_liquidityPools[i].strength > bestStrength)
           {
            bestStrength = m_liquidityPools[i].strength;
            bestPrice = m_liquidityPools[i].priceLevel;
           }
        }
      else
         if(!buyDirection && m_liquidityPools[i].bullish && m_liquidityPools[i].priceLevel < currentPrice)
           {
            if(m_liquidityPools[i].strength > bestStrength)
              {
               bestStrength = m_liquidityPools[i].strength;
               bestPrice = m_liquidityPools[i].priceLevel;
              }
           }
     }
   if(bestPrice == 0.0)
     {
      if(buyDirection)
        {
         double best = DBL_MAX;
         for(int i = 0; i < m_totalOB; i++)
            if(!m_orderBlocks[i].mitigated && !m_orderBlocks[i].bullish &&
               m_orderBlocks[i].low > currentPrice && m_orderBlocks[i].low < best)
               best = m_orderBlocks[i].low;
         for(int i = 0; i < m_totalFVG; i++)
            if(!m_fairValueGaps[i].mitigated && !m_fairValueGaps[i].bullish &&
               m_fairValueGaps[i].gapLow > currentPrice && m_fairValueGaps[i].gapLow < best)
               best = m_fairValueGaps[i].gapLow;
         if(best != DBL_MAX)
            bestPrice = best;
        }
      else
        {
         double best = -1.0;
         for(int i = 0; i < m_totalOB; i++)
            if(!m_orderBlocks[i].mitigated && m_orderBlocks[i].bullish &&
               m_orderBlocks[i].high < currentPrice && m_orderBlocks[i].high > best)
               best = m_orderBlocks[i].high;
         for(int i = 0; i < m_totalFVG; i++)
            if(!m_fairValueGaps[i].mitigated && m_fairValueGaps[i].bullish &&
               m_fairValueGaps[i].gapHigh < currentPrice && m_fairValueGaps[i].gapHigh > best)
               best = m_fairValueGaps[i].gapHigh;
         if(best > 0.0)
            bestPrice = best;
        }
     }
   return bestPrice;
  }

//+------------------------------------------------------------------+
//| GetMacroDirection (VERSIÓN CORREGIDA: solo -0.5, 0, 0.5)         |
//+------------------------------------------------------------------+
double SmartMoney::GetMacroDirection(int start_bar = 0)
  {
   double baseDir = m_macroDirection;
   double adx = GetADX(start_bar);
   double rsi = GetRSI(start_bar);
   double momentum = CalculateMomentum(20, PERIOD_M15, start_bar);

   if(baseDir == 1)
      return 0.5;
   if(baseDir == -1)
      return -0.5;

   if(adx >= 12.0)
     {
      if(rsi > 53.0 && momentum > 0.0)
         return 0.5;
      else
         if(rsi < 47.0 && momentum < 0.0)
            return -0.5;
         else
            if(rsi > 50.0)
               return 0.5;
            else
               if(rsi < 50.0)
                  return -0.5;
     }

   if(momentum > 0.02 && rsi > 45.0)
      return 0.5;
   else
      if(momentum < -0.02 && rsi < 55.0)
         return -0.5;
      else
         if(momentum > 0.05)
            return 0.5;
         else
            if(momentum < -0.05)
               return -0.5;

   return 0.0;
  }

//+------------------------------------------------------------------+
//| Metodos de consulta de mitigacion                                 |
//+------------------------------------------------------------------+
bool SmartMoney::IsOBMitigated(double price, bool buyDirection) const
  {
   for(int i = 0; i < m_totalOB; i++)
      if(!m_orderBlocks[i].mitigated && buyDirection == m_orderBlocks[i].bullish &&
         price >= m_orderBlocks[i].low && price <= m_orderBlocks[i].high)
         return true;
   return false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool SmartMoney::IsFVGMitigated(double price, bool buyDirection) const
  {
   for(int i = 0; i < m_totalFVG; i++)
      if(!m_fairValueGaps[i].mitigated && buyDirection == m_fairValueGaps[i].bullish &&
         price >= m_fairValueGaps[i].gapLow && price <= m_fairValueGaps[i].gapHigh)
         return true;
   return false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double SmartMoney::GetOBMitigationRatio(double price, bool buyDirection) const
  {
   for(int i = 0; i < m_totalOB; i++)
      if(!m_orderBlocks[i].mitigated && buyDirection == m_orderBlocks[i].bullish &&
         price >= m_orderBlocks[i].low && price <= m_orderBlocks[i].high)
        {
         double range = m_orderBlocks[i].high - m_orderBlocks[i].low;
         return (range == 0.0) ? 1.0 : (price - m_orderBlocks[i].low) / range;
        }
   return 0.0;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int SmartMoney::GetActiveOrderBlocks() const
  { int c=0; for(int i=0;i<m_totalOB;i++) if(!m_orderBlocks[i].mitigated) c++; return c; }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int SmartMoney::GetActiveFairValueGaps() const
  { int c=0; for(int i=0;i<m_totalFVG;i++) if(!m_fairValueGaps[i].mitigated) c++; return c; }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int SmartMoney::GetRefinedZoneCount() const
  {
   int c=0;
   for(int i=0;i<m_totalOB;i++)
      if(!m_orderBlocks[i].mitigated && m_orderBlocks[i].refined)
         c++;
   for(int i=0;i<m_totalFVG;i++)
      if(!m_fairValueGaps[i].mitigated && m_fairValueGaps[i].refined)
         c++;
   return c;
  }

//+------------------------------------------------------------------+
//| Indicadores basicos (sin sesgos, devuelven 0.0 en error)         |
//+------------------------------------------------------------------+
double SmartMoney::GetATR(int period = 14, int start_bar = 0)
  {
   EnsureIndicators();
   if(m_handleATR == INVALID_HANDLE)
      return 0.0;
   double buf[1];
   return (CopyBuffer(m_handleATR, 0, start_bar, 1, buf) == 1) ? buf[0] : 0.0;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double SmartMoney::GetADX(int start_bar = 0)
  {
   EnsureIndicators();
   if(m_handleADX == INVALID_HANDLE)
      return 0.0;
   double buf[1];
   return (CopyBuffer(m_handleADX, 0, start_bar, 1, buf) == 1) ? buf[0] : 0.0;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double SmartMoney::GetRSI(int start_bar = 0)
  {
   EnsureIndicators();
   if(m_handleRSI == INVALID_HANDLE)
      return 50.0;
   double buf[1];
   return (CopyBuffer(m_handleRSI, 0, start_bar, 1, buf) == 1) ? buf[0] : 50.0;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double SmartMoney::CalculateMomentum(int lookback = 20, ENUM_TIMEFRAMES tf = PERIOD_M15, int start_bar = 0)
  {
   double closeCurrent[1], closePast[1];
   if(CopyClose(m_symbol, tf, start_bar, 1, closeCurrent) != 1)
      return 0.0;
   if(CopyClose(m_symbol, tf, start_bar + lookback, 1, closePast) != 1)
      return 0.0;
   double atr = GetATR(14, start_bar);
   if(atr == 0.0)
      return 0.0;
   return (closeCurrent[0] - closePast[0]) / (atr * lookback + 0.0001);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double SmartMoney::CalculateVolumeFlow(int lookback = 20, ENUM_TIMEFRAMES tf = PERIOD_M15, int start_bar = 0)
  {
   long tickVol[1];
   if(CopyTickVolume(m_symbol, tf, start_bar, 1, tickVol) != 1)
      return 0.0;
   double closeCurrent[1], closePast[1];
   if(CopyClose(m_symbol, tf, start_bar, 1, closeCurrent) != 1)
      return 0.0;
   if(CopyClose(m_symbol, tf, start_bar + 1, 1, closePast) != 1)
      return 0.0;
   double atr = GetATR(14, start_bar);
   if(atr == 0.0 || closeCurrent[0] == 0.0)
      return 0.0;
   return (tickVol[0] * (closeCurrent[0] - closePast[0])) / (atr * closeCurrent[0] + 0.0001);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double SmartMoney::CalculateRegressionSlope(int lookback = 20, ENUM_TIMEFRAMES tf = PERIOD_M1)
  {
   double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
   for(int i = 0; i < lookback; i++)
     {
      double high[], low[];
      if(CopyHigh(m_symbol, tf, i, 1, high) != 1 || CopyLow(m_symbol, tf, i, 1, low) != 1)
         break;
      double mid = (high[0] + low[0]) / 2.0;
      sumX += i;
      sumY += mid;
      sumXY += i * mid;
      sumX2 += i * i;
     }
   double denom = lookback * sumX2 - sumX * sumX;
   return (denom == 0.0) ? 0.0 : (lookback * sumXY - sumX * sumY) / denom;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double SmartMoney::CalculateChoppinessIndex(int periods = 14)
  {
// Usar cache si es posible
   if(m_lastChopCalcTime != 0 && TimeCurrent() - m_lastChopCalcTime < CHOP_CACHE_SECONDS)
      return m_lastChopValue;

   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(m_handleATR, 0, 0, MathMin(periods, 1000), atrBuf) < MathMin(periods, 1000))
      return 50.0;
   double sumATR = 0.0;
   int copyCount = ArraySize(atrBuf);
   for(int i = 0; i < copyCount; i++)
      sumATR += atrBuf[i];
   double highs[], lows[];
   if(CopyHigh(m_symbol, PERIOD_M15, 0, MathMin(periods, 1000), highs) < MathMin(periods, 1000))
      return 50.0;
   if(CopyLow(m_symbol, PERIOD_M15, 0, MathMin(periods, 1000), lows) < MathMin(periods, 1000))
      return 50.0;
   double maxHigh = highs[ArrayMaximum(highs, 0, copyCount)];
   double minLow  = lows[ArrayMinimum(lows, 0, copyCount)];
   double range = maxHigh - minLow;
   if(range == 0.0 || sumATR == 0.0)
      return 100.0;
   double ratio = sumATR / (range + 0.0001);
   double logRatio = MathLog10(ratio);
   double logN = MathLog10(periods);
   double result = (logN == 0.0) ? 0.0 : 100.0 * logRatio / logN;

   m_lastChopCalcTime = TimeCurrent();
   m_lastChopValue = result;
   return result;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool SmartMoney::ValidateChoppinessFilter(int periods = 14)
  {
   double ci = CalculateChoppinessIndex(periods);
   return (ci <= 61.8 && ci >= 38.2);
  }

//+------------------------------------------------------------------+
//| Persistencia                                                      |
//+------------------------------------------------------------------+
bool SmartMoney::SaveState(string fileName)
  {
   int handle = FileOpen(fileName, FILE_BIN | FILE_WRITE);
   if(handle == INVALID_HANDLE)
      return false;
   FileWriteInteger(handle, m_totalOB);
   FileWriteInteger(handle, m_totalFVG);
   FileWriteInteger(handle, m_totalPools);
   FileWriteDouble(handle, m_macroDirection);
   FileWriteDouble(handle, m_macroStrength);
   FileWriteDouble(handle, m_atrBase);
   FileWriteArray(handle, m_orderBlocks, 0, m_totalOB);
   FileWriteArray(handle, m_fairValueGaps, 0, m_totalFVG);
   FileWriteArray(handle, m_liquidityPools, 0, m_totalPools);
   FileClose(handle);
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool SmartMoney::LoadState(string fileName)
  {
   int handle = FileOpen(fileName, FILE_BIN | FILE_READ);
   if(handle == INVALID_HANDLE)
      return false;
   m_totalOB = FileReadInteger(handle);
   m_totalFVG = FileReadInteger(handle);
   m_totalPools = FileReadInteger(handle);
   m_macroDirection = FileReadDouble(handle);
   m_macroStrength = FileReadDouble(handle);
   m_atrBase = FileReadDouble(handle);
   ArrayResize(m_orderBlocks, m_totalOB);
   ArrayResize(m_fairValueGaps, m_totalFVG);
   ArrayResize(m_liquidityPools, m_totalPools);
   FileReadArray(handle, m_orderBlocks, 0, m_totalOB);
   FileReadArray(handle, m_fairValueGaps, 0, m_totalFVG);
   FileReadArray(handle, m_liquidityPools, 0, m_totalPools);
   FileClose(handle);
   return true;
  }

//+------------------------------------------------------------------+
//| Configuracion de umbrales                                         |
//+------------------------------------------------------------------+
void SmartMoney::SetTrainingThresholds(double adxWeak, double adxStrong, double momStrong)
  {
   m_adxWeak   = adxWeak;
   m_adxStrong = adxStrong;
   m_momStrong = momStrong;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SmartMoney::SetDetectionFactors(double obBodyFactor, double fvgGapFactor)
  {
   m_obBodyFactor = obBodyFactor;
   m_fvgGapFactor = fvgGapFactor;
  }

const int SmartMoney::CHOP_CACHE_SECONDS = 60;

#endif // __SMARTMONEY_MQH__
//+------------------------------------------------------------------+
