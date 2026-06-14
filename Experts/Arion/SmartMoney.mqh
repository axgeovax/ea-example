//+------------------------------------------------------------------+
//|                                                 SmartMoney.mqh   |
//|                        Arion - SMC Fractal Dinámico v1.0         |
//|        Detección agnóstica al tiempo, arrays dinámicos,          |
//|        zonas anidadas, validación por velocidad, liquidity pools |
//|                        Autor: Alexy Hernández                    |
//|                        Versión: 1.0                              |
//|        Copyright (c) 2025 Alexy Hernández. Todos los derechos    |
//|        reservados.                                               |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernández. Todos los derechos reservados."
#property link      "https://github.com/axgeovax"
#property version   "1.0"
#property strict

#ifndef __SMARTMONEY_MQH__
#define __SMARTMONEY_MQH__

//+------------------------------------------------------------------+
//| Estructura de Order Block mejorada                                |
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

//+------------------------------------------------------------------+
//| Estructura de Fair Value Gap mejorada                             |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Estructura de Liquidity Pool                                     |
//+------------------------------------------------------------------+
struct LiquidityPool
  {
   double            priceLevel;
   bool              bullish;         // true = resistencia, false = soporte
   int               zoneCount;
   double            totalVolume;
   double            strength;        // 0-1
  };

//+------------------------------------------------------------------+
//| Clase SmartMoney – SMC Fractal Dinámico                          |
//+------------------------------------------------------------------+
class SmartMoney
  {
private:
   string            m_symbol;
   double            m_atrBase;
   double            m_atrMultiplier;
   int               m_maxSlots;
   int               m_maxPoolSlots;

   OrderBlock        m_orderBlocks[];
   int               m_totalOB;
   FairValueGap      m_fairValueGaps[];
   int               m_totalFVG;

   LiquidityPool     m_liquidityPools[];
   int               m_totalPools;

   int               m_macroDirection;    // -1, 0, 1
   double            m_macroStrength;

   int               m_handleATR;
   int               m_handleADX;
   int               m_handleRSI;
   bool              m_indicatorsReady;

   // Umbrales ajustables para GetMacroDirection()
   double            m_adxWeak;      // Valor por defecto 25.0
   double            m_adxStrong;    // Valor por defecto 40.0
   double            m_momStrong;    // Valor por defecto 1.0

   void              EnsureIndicators();
   bool              DetectFractalStructure(int start_bar = 0);
   double            CalculateRelevance(datetime time, double volumeFlow, int scale);
   void              PruneLowRelevanceZones();
   void              DetectNestedZones();
   void              UpdateMitigationState(int start_bar = 0);
   void              BuildLiquidityPools();
   void              AddToPool(double price, bool bullish, double volume);

public:
                     SmartMoney(string symbol = NULL);
                    ~SmartMoney() { Cleanup(); }

   bool              Initialize();

   // --- Compatibilidad con versión anterior (parámetros ignorados) ---
   void              UpdateStructure(bool newMacro, bool newZona);

   // --- Nueva lógica continua (con desplazamiento opcional) ---
   void              UpdateStructure(int start_bar = 0);

   void              Cleanup();

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

   // --- Ajuste temporal de umbrales para recolección de datos ---
   void              SetTrainingThresholds(double adxWeak, double adxStrong, double momStrong);
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
   m_handleADX = INVALID_HANDLE;
   m_handleRSI = INVALID_HANDLE;
   m_indicatorsReady = false;

// Umbrales por defecto (estrictos para el EA)
   m_adxWeak   = 25.0;
   m_adxStrong = 40.0;
   m_momStrong = 1.0;

   ArrayResize(m_orderBlocks, 0);
   ArrayResize(m_fairValueGaps, 0);
   ArrayResize(m_liquidityPools, 0);
  }

//+------------------------------------------------------------------+
//| Inicializar indicadores                                            |
//+------------------------------------------------------------------+
void SmartMoney::EnsureIndicators()
  {
   if(m_indicatorsReady)
      return;

   if(m_handleATR == INVALID_HANDLE)
      m_handleATR = iATR(m_symbol, PERIOD_M15, 14);
   if(m_handleADX == INVALID_HANDLE)
      m_handleADX = iADX(m_symbol, PERIOD_M15, 14);
   if(m_handleRSI == INVALID_HANDLE)
      m_handleRSI = iRSI(m_symbol, PERIOD_M15, 14, PRICE_CLOSE);

   m_indicatorsReady = (m_handleATR != INVALID_HANDLE &&
                        m_handleADX != INVALID_HANDLE &&
                        m_handleRSI != INVALID_HANDLE);
  }

//+------------------------------------------------------------------+
//| Inicializar                                                        |
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
//| Limpiar recursos                                                   |
//+------------------------------------------------------------------+
void SmartMoney::Cleanup()
  {
   if(m_handleATR != INVALID_HANDLE)
      IndicatorRelease(m_handleATR);
   if(m_handleADX != INVALID_HANDLE)
      IndicatorRelease(m_handleADX);
   if(m_handleRSI != INVALID_HANDLE)
      IndicatorRelease(m_handleRSI);
   m_indicatorsReady = false;
  }

//+------------------------------------------------------------------+
//| Actualizar estructura (compatibilidad con v1.0)                    |
//+------------------------------------------------------------------+
void SmartMoney::UpdateStructure(bool newMacro, bool newZona)
  {
   UpdateStructure(0);
  }

//+------------------------------------------------------------------+
//| Actualizar estructura (con desplazamiento opcional)               |
//+------------------------------------------------------------------+
void SmartMoney::UpdateStructure(int start_bar = 0)
  {
   DetectFractalStructure(start_bar);
  }

//+------------------------------------------------------------------+
//| Detección fractal agnóstica al tiempo (start_bar añadido)         |
//+------------------------------------------------------------------+
bool SmartMoney::DetectFractalStructure(int start_bar = 0)
  {
   EnsureIndicators();
   if(!m_indicatorsReady)
      return false;

   double atrBuf[1];
   if(CopyBuffer(m_handleATR, 0, start_bar, 1, atrBuf) != 1)
      return false;
   m_atrBase = atrBuf[0];
   if(m_atrBase <= 0)
      return false;

   MqlRates rates[];
   int copied = CopyRates(m_symbol, PERIOD_CURRENT, start_bar, 100, rates);
   if(copied <= 20)
      return false;
   ArraySetAsSeries(rates, true);

   if(ArraySize(rates) < copied)
      copied = ArraySize(rates);
   if(copied < 21)
      return false;

   double swingThreshold = m_atrBase * m_atrMultiplier;
   int lastSwingHigh = -1, lastSwingLow = -1;
   double lastHighPrice = 0, lastLowPrice = 0;

   m_totalOB = 0;
   m_totalFVG = 0;
   ArrayResize(m_orderBlocks, 0);
   ArrayResize(m_fairValueGaps, 0);

   int limit = MathMin(copied - 3, 50);
   for(int i = 5; i < limit; i++)
     {
      if(i+2 >= copied || i-2 < 0)
         continue;

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

      // --- Order Blocks ---
      if(i >= 1 && i < copied - 1)
        {
         if(rates[i].close < rates[i].open && rates[i-1].close > rates[i-1].open)
           {
            double body = MathAbs(rates[i].close - rates[i].open);
            if(body > m_atrBase * 0.5)
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
               if(body > m_atrBase * 0.5)
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

         // --- Fair Value Gaps ---
         if(i+2 < copied)
           {
            if(rates[i].low > rates[i+2].high)
              {
               double gapHigh = rates[i].low;
               double gapLow = rates[i+2].high;
               double gapSize = gapHigh - gapLow;
               if(gapSize > m_atrBase * 0.2)
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
                  if(gapSize > m_atrBase * 0.2)
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

   for(int i = 0; i < m_totalOB; i++)
      m_orderBlocks[i].relevance = CalculateRelevance(m_orderBlocks[i].time, m_orderBlocks[i].volumeFlow, m_orderBlocks[i].scale);
   for(int i = 0; i < m_totalFVG; i++)
      m_fairValueGaps[i].relevance = CalculateRelevance(m_fairValueGaps[i].time, m_fairValueGaps[i].volumeFlow, m_fairValueGaps[i].scale);

   PruneLowRelevanceZones();
   DetectNestedZones();
   UpdateMitigationState(start_bar);
   BuildLiquidityPools();

   return true;
  }

//+------------------------------------------------------------------+
//| Calcular relevancia (0-100)                                        |
//+------------------------------------------------------------------+
double SmartMoney::CalculateRelevance(datetime time, double volumeFlow, int scale)
  {
   double ageHours = (double)(TimeCurrent() - time) / 3600.0;
   double ageScore = MathMax(0.0, 100.0 - ageHours * 1.5);
   double scaleScore = (scale == 2) ? 100.0 : (scale == 1) ? 70.0 : 40.0;
   double volScore = MathMin(100.0, MathAbs(volumeFlow) / (m_atrBase + 1e-9) * 30.0);
   return ageScore * 0.4 + scaleScore * 0.35 + volScore * 0.25;
  }

//+------------------------------------------------------------------+
//| Podar zonas de baja relevancia                                     |
//+------------------------------------------------------------------+
void SmartMoney::PruneLowRelevanceZones()
  {
   if(m_maxSlots <= 0)
      return;

   while(m_totalOB > m_maxSlots)
     {
      int worstIdx = 0;
      double worstRel = 999.0;
      for(int i = 0; i < m_totalOB; i++)
        {
         if(m_orderBlocks[i].relevance < worstRel)
           {
            worstRel = m_orderBlocks[i].relevance;
            worstIdx = i;
           }
        }
      for(int i = worstIdx; i < m_totalOB - 1; i++)
         m_orderBlocks[i] = m_orderBlocks[i+1];
      m_totalOB--;
      ArrayResize(m_orderBlocks, m_totalOB);
     }

   while(m_totalFVG > m_maxSlots)
     {
      int worstIdx = 0;
      double worstRel = 999.0;
      for(int i = 0; i < m_totalFVG; i++)
        {
         if(m_fairValueGaps[i].relevance < worstRel)
           {
            worstRel = m_fairValueGaps[i].relevance;
            worstIdx = i;
           }
        }
      for(int i = worstIdx; i < m_totalFVG - 1; i++)
         m_fairValueGaps[i] = m_fairValueGaps[i+1];
      m_totalFVG--;
      ArrayResize(m_fairValueGaps, m_totalFVG);
     }
  }

//+------------------------------------------------------------------+
//| Detectar zonas anidadas (Nested OBs)                               |
//+------------------------------------------------------------------+
void SmartMoney::DetectNestedZones()
  {
   for(int i = 0; i < m_totalOB; i++)
     {
      if(m_orderBlocks[i].mitigated)
         continue;
      for(int j = 0; j < m_totalOB; j++)
        {
         if(i == j || m_orderBlocks[j].mitigated)
            continue;
         if(m_orderBlocks[j].scale <= m_orderBlocks[i].scale)
            continue;
         if(m_orderBlocks[i].high <= m_orderBlocks[j].high &&
            m_orderBlocks[i].low >= m_orderBlocks[j].low &&
            m_orderBlocks[i].bullish == m_orderBlocks[j].bullish)
           {
            m_orderBlocks[i].refined = true;
            break;
           }
        }
     }
   for(int i = 0; i < m_totalFVG; i++)
     {
      if(m_fairValueGaps[i].mitigated)
         continue;
      for(int j = 0; j < m_totalFVG; j++)
        {
         if(i == j || m_fairValueGaps[j].mitigated)
            continue;
         if(m_fairValueGaps[j].scale <= m_fairValueGaps[i].scale)
            continue;
         if(m_fairValueGaps[i].gapHigh <= m_fairValueGaps[j].gapHigh &&
            m_fairValueGaps[i].gapLow >= m_fairValueGaps[j].gapLow &&
            m_fairValueGaps[i].bullish == m_fairValueGaps[j].bullish)
           {
            m_fairValueGaps[i].refined = true;
            break;
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Actualizar mitigación (ahora acepta start_bar)                    |
//+------------------------------------------------------------------+
void SmartMoney::UpdateMitigationState(int start_bar = 0)
  {
   double price;
   if(start_bar == 0)
     {
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      price = (ask + bid) / 2.0;
     }
   else
     {
      double close[1];
      if(CopyClose(m_symbol, PERIOD_CURRENT, start_bar, 1, close) != 1)
         return;
      price = close[0];
     }

   for(int i = 0; i < m_totalOB; i++)
     {
      if(m_orderBlocks[i].mitigated)
         continue;
      if((m_orderBlocks[i].bullish && price < m_orderBlocks[i].low) ||
         (!m_orderBlocks[i].bullish && price > m_orderBlocks[i].high))
         m_orderBlocks[i].mitigated = true;
     }
   for(int i = 0; i < m_totalFVG; i++)
     {
      if(m_fairValueGaps[i].mitigated)
         continue;
      if((m_fairValueGaps[i].bullish && price < m_fairValueGaps[i].gapLow) ||
         (!m_fairValueGaps[i].bullish && price > m_fairValueGaps[i].gapHigh))
         m_fairValueGaps[i].mitigated = true;
     }
  }

//+------------------------------------------------------------------+
//| Construir Liquidity Pools (incluye FVGs)                          |
//+------------------------------------------------------------------+
void SmartMoney::BuildLiquidityPools()
  {
   ArrayResize(m_liquidityPools, 0);
   m_totalPools = 0;

   for(int i = 0; i < m_totalOB; i++)
     {
      if(m_orderBlocks[i].mitigated)
         continue;
      double price = m_orderBlocks[i].bullish ? m_orderBlocks[i].low : m_orderBlocks[i].high;
      AddToPool(price, m_orderBlocks[i].bullish, m_orderBlocks[i].volumeFlow);
     }
   for(int i = 0; i < m_totalFVG; i++)
     {
      if(m_fairValueGaps[i].mitigated)
         continue;
      double price = m_fairValueGaps[i].bullish ? m_fairValueGaps[i].gapLow : m_fairValueGaps[i].gapHigh;
      AddToPool(price, m_fairValueGaps[i].bullish, m_fairValueGaps[i].volumeFlow);
     }

   for(int i = 0; i < m_totalPools; i++)
     {
      m_liquidityPools[i].strength = MathMin(1.0,
                                             (double)m_liquidityPools[i].zoneCount / 5.0 * 0.6 +
                                             m_liquidityPools[i].totalVolume / (m_atrBase * 1000 + 1e-9) * 0.4);
     }
  }

//+------------------------------------------------------------------+
//| Añadir zona a Liquidity Pool                                       |
//+------------------------------------------------------------------+
void SmartMoney::AddToPool(double price, bool bullish, double volume)
  {
   double tolerance = m_atrBase * 0.3;

   for(int i = 0; i < m_totalPools; i++)
     {
      if(m_liquidityPools[i].bullish == bullish &&
         MathAbs(m_liquidityPools[i].priceLevel - price) < tolerance)
        {
         m_liquidityPools[i].zoneCount++;
         m_liquidityPools[i].totalVolume += volume;
         m_liquidityPools[i].priceLevel = (m_liquidityPools[i].priceLevel * (m_liquidityPools[i].zoneCount - 1) + price) / m_liquidityPools[i].zoneCount;
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
//| Liquidez opuesta avanzada (usa Liquidity Pools)                    |
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
//| Dirección macro con 5 niveles (umbrales ajustables, start_bar)    |
//+------------------------------------------------------------------+
double SmartMoney::GetMacroDirection(int start_bar = 0)
  {
   int baseDir = m_macroDirection;
   if(baseDir == 0)
      return 0.0;

   double adx = GetADX(start_bar);
   double rsi = GetRSI(start_bar);
   double momentum = CalculateMomentum(20, PERIOD_M15, start_bar);

   if(baseDir == -1)
     {
      if(adx < m_adxWeak)
         return 0.0;
      if(adx < m_adxStrong)
         return -0.5;
      if(momentum < -m_momStrong && rsi < 40.0)
         return -1.0;
      return -0.5;
     }
   else
      if(baseDir == 1)
        {
         if(adx < m_adxWeak)
            return 0.0;
         if(adx < m_adxStrong)
            return 0.5;
         if(momentum > m_momStrong && rsi > 60.0)
            return 1.0;
         return 0.5;
        }

   if(baseDir == 1 && momentum > 0.0)
      return 0.5;
   if(baseDir == -1 && momentum < 0.0)
      return -0.5;

   return 0.0;
  }

//+------------------------------------------------------------------+
//| Configurar umbrales para entrenamiento (más sensibles)            |
//+------------------------------------------------------------------+
void SmartMoney::SetTrainingThresholds(double adxWeak, double adxStrong, double momStrong)
  {
   m_adxWeak   = adxWeak;
   m_adxStrong = adxStrong;
   m_momStrong = momStrong;
  }

//+------------------------------------------------------------------+
//| Métodos de consulta                                                |
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
  {
   int count = 0;
   for(int i = 0; i < m_totalOB; i++)
      if(!m_orderBlocks[i].mitigated)
         count++;
   return count;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int SmartMoney::GetActiveFairValueGaps() const
  {
   int count = 0;
   for(int i = 0; i < m_totalFVG; i++)
      if(!m_fairValueGaps[i].mitigated)
         count++;
   return count;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int SmartMoney::GetRefinedZoneCount() const
  {
   int count = 0;
   for(int i = 0; i < m_totalOB; i++)
      if(!m_orderBlocks[i].mitigated && m_orderBlocks[i].refined)
         count++;
   for(int i = 0; i < m_totalFVG; i++)
      if(!m_fairValueGaps[i].mitigated && m_fairValueGaps[i].refined)
         count++;
   return count;
  }

//+------------------------------------------------------------------+
//| Métricas originales (con start_bar opcional)                      |
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
      return 0.0;
   double buf[1];
   return (CopyBuffer(m_handleRSI, 0, start_bar, 1, buf) == 1) ? buf[0] : 0.0;
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
   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(m_handleATR, 0, 0, periods, atrBuf) < periods)
      return 0.0;

   double sumATR = 0.0;
   for(int i = 0; i < periods; i++)
      sumATR += atrBuf[i];

   double highs[];
   double lows[];
   if(CopyHigh(m_symbol, PERIOD_M15, 0, periods, highs) < periods)
      return 0.0;
   if(CopyLow(m_symbol, PERIOD_M15, 0, periods, lows) < periods)
      return 0.0;

   double maxHigh = highs[ArrayMaximum(highs, 0, periods)];
   double minLow  = lows[ArrayMinimum(lows, 0, periods)];
   double range = maxHigh - minLow;

   if(range == 0.0 || sumATR == 0.0)
      return 100.0;

   double ratio = sumATR / (range + 0.0001);
   double logRatio = MathLog10(ratio);
   double logN = MathLog10(periods);
   return (logN == 0.0) ? 0.0 : 100.0 * logRatio / logN;
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
//| Persistencia (compatible con sistema de archivos)                  |
//+------------------------------------------------------------------+
bool SmartMoney::SaveState(string fileName)
  {
   int handle = FileOpen(fileName, FILE_BIN | FILE_WRITE);
   if(handle == INVALID_HANDLE)
     {
      Print("Error [SmartMoney] saving ", fileName, ": ", GetLastError());
      return false;
     }

   FileWriteInteger(handle, m_totalOB);
   FileWriteInteger(handle, m_totalFVG);
   FileWriteInteger(handle, m_totalPools);
   FileWriteInteger(handle, m_macroDirection);
   FileWriteDouble(handle, m_macroStrength);
   FileWriteDouble(handle, m_atrBase);

   FileWriteArray(handle, m_orderBlocks, 0, m_totalOB);
   FileWriteArray(handle, m_fairValueGaps, 0, m_totalFVG);
   FileWriteArray(handle, m_liquidityPools, 0, m_totalPools);

   FileClose(handle);
   Print("SmartMoney state saved to ", fileName);
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
   m_macroDirection = FileReadInteger(handle);
   m_macroStrength = FileReadDouble(handle);
   m_atrBase = FileReadDouble(handle);

   if(m_totalOB < 0 || m_totalOB > 10000 || m_totalFVG < 0 || m_totalFVG > 10000 ||
      m_totalPools < 0 || m_totalPools > 100)
     {
      Print("Error [SmartMoney]: corrupted data in ", fileName);
      FileClose(handle);
      return false;
     }

   ArrayResize(m_orderBlocks, m_totalOB);
   ArrayResize(m_fairValueGaps, m_totalFVG);
   ArrayResize(m_liquidityPools, m_totalPools);

   FileReadArray(handle, m_orderBlocks, 0, m_totalOB);
   FileReadArray(handle, m_fairValueGaps, 0, m_totalFVG);
   FileReadArray(handle, m_liquidityPools, 0, m_totalPools);
   FileClose(handle);

   Print("SmartMoney state loaded from ", fileName);
   return true;
  }

#endif // __SMARTMONEY_MQH__
//+------------------------------------------------------------------+
