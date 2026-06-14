//+------------------------------------------------------------------+
//|                                          CorrelationEngine.mqh   |
//|                        Arion - Motor de Correlación Multicapa    |
//|        Matriz Dual (D1 + M15), Alpha Detection,                  |
//|        Recálculo por Volatilidad, Factor de Reducción Adaptativo |
//|                        Autor: Alexy Hernández                    |
//|                        Versión: 1.0                              |
//|        Copyright (c) 2025 Alexy Hernández. Todos los derechos    |
//|        reservados.                                               |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernández. Todos los derechos reservados."
#property link      "https://github.com/axgeovax"
#property version   "1.0"
#property strict

#ifndef __CORRELATIONENGINE_MQH__
#define __CORRELATIONENGINE_MQH__

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class CorrelationEngine
  {
private:
   string            m_symbols[];
   int               m_total;

   // --- Macro (D1) ---
   double            m_matrixD1[];          // plano [total * total]
   bool              m_updatedD1;
   datetime          m_lastUpdateD1;
   double            m_pricesD1[];          // plano [total * 100]
   bool              m_synchronizedD1[];

   // --- Intradía (M15) ---
   double            m_matrixM15[];         // plano [total * total]
   bool              m_updatedM15;
   datetime          m_lastUpdateM15;
   double            m_pricesM15[];         // plano [total * 50]
   bool              m_synchronizedM15[];

   // --- Volatilidad / desacople ---
   double            m_lastAvgSpread;
   double            m_lastPortfolioATR;
   bool              m_decouplingFlags[];   // plano [total * total]
   int               m_decouplingCount;

   // Indexación plana
   int               Idx(int row, int col) const { return row * m_total + col; }
   int               IdxD1(int row, int bar) const { return row * 100 + bar; }
   int               IdxM15(int row, int bar) const { return row * 50 + bar; }

   void              VerifySynchronization();
   void              UpdateMatrixD1();
   void              UpdateMatrixM15();
   double            CalculatePortfolioATR();
   int               GetSymbolIndex(string sym);   // declaración

public:
                     CorrelationEngine();
                    ~CorrelationEngine() {}

   void              Initialize(string &assets[], int total);
   void              UpdateCorrelationMatrix();

   double            GetCorrelation(string sym1, string sym2);
   double            GetCorrelationM15(string sym1, string sym2);

   bool              IsUpdated() const { return m_updatedD1; }
   bool              IsUpdatedM15() const { return m_updatedM15; }
   double            GetLastAvgSpread() const { return m_lastAvgSpread; }

   bool              IsFlashDecoupling(string sym1, string sym2);
   int               GetDecouplingCount() const { return m_decouplingCount; }
   double            GetAdaptiveReductionFactor(string sym1, string sym2);
  };

//+------------------------------------------------------------------+
//| Constructor                                                        |
//+------------------------------------------------------------------+
CorrelationEngine::CorrelationEngine()
  {
   m_total = 0;
   m_updatedD1 = false;
   m_updatedM15 = false;
   m_lastUpdateD1 = 0;
   m_lastUpdateM15 = 0;
   m_lastAvgSpread = 0.0;
   m_lastPortfolioATR = 0.0;
   m_decouplingCount = 0;

   ArrayResize(m_symbols, 0);
   ArrayResize(m_matrixD1, 0);
   ArrayResize(m_matrixM15, 0);
   ArrayResize(m_pricesD1, 0);
   ArrayResize(m_pricesM15, 0);
   ArrayResize(m_synchronizedD1, 0);
   ArrayResize(m_synchronizedM15, 0);
   ArrayResize(m_decouplingFlags, 0);
  }

//+------------------------------------------------------------------+
//| Inicializar lista de símbolos (dinámico)                          |
//+------------------------------------------------------------------+
void CorrelationEngine::Initialize(string &assets[], int total)
  {
   if(total <= 0)
     {
      Print("Error [CorrelationEngine]: total must be > 0");
      return;
     }

   m_total = total;

   ArrayResize(m_symbols, m_total);
   ArrayResize(m_matrixD1, m_total * m_total);
   ArrayResize(m_matrixM15, m_total * m_total);
   ArrayResize(m_pricesD1, m_total * 100);
   ArrayResize(m_pricesM15, m_total * 50);
   ArrayResize(m_synchronizedD1, m_total);
   ArrayResize(m_synchronizedM15, m_total);
   ArrayResize(m_decouplingFlags, m_total * m_total);

   for(int i = 0; i < m_total; i++)
     {
      m_symbols[i] = assets[i];
      m_matrixD1[Idx(i, i)] = 1.0;
      m_matrixM15[Idx(i, i)] = 1.0;
     }

   ArrayInitialize(m_pricesD1, 0.0);
   ArrayInitialize(m_pricesM15, 0.0);
   ArrayInitialize(m_decouplingFlags, false);
   ArrayInitialize(m_synchronizedD1, false);
   ArrayInitialize(m_synchronizedM15, false);

   VerifySynchronization();
  }

//+------------------------------------------------------------------+
//| Verificar sincronización                                          |
//+------------------------------------------------------------------+
void CorrelationEngine::VerifySynchronization()
  {
   for(int i = 0; i < m_total; i++)
     {
      m_synchronizedD1[i]  = SeriesInfoInteger(m_symbols[i], PERIOD_D1,  SERIES_SYNCHRONIZED);
      m_synchronizedM15[i] = SeriesInfoInteger(m_symbols[i], PERIOD_M15, SERIES_SYNCHRONIZED);
     }
  }

//+------------------------------------------------------------------+
//| ATR promedio del portafolio (M15)                                 |
//+------------------------------------------------------------------+
double CorrelationEngine::CalculatePortfolioATR()
  {
   double sumATR = 0.0;
   int count = 0;
   for(int i = 0; i < m_total; i++)
     {
      int handle = iATR(m_symbols[i], PERIOD_M15, 14);
      if(handle != INVALID_HANDLE)
        {
         double buf[1];
         if(CopyBuffer(handle, 0, 0, 1, buf) == 1)
           {
            sumATR += buf[0];
            count++;
           }
         IndicatorRelease(handle);
        }
     }
   return (count > 0) ? sumATR / count : 0.0;
  }

//+------------------------------------------------------------------+
//| Actualizar matriz D1 (100 barras)                                 |
//+------------------------------------------------------------------+
void CorrelationEngine::UpdateMatrixD1()
  {
   if(m_total < 2)
      return;

   for(int i = 0; i < m_total; i++)
     {
      if(!m_synchronizedD1[i])
         continue;
      double temp[];
      ArrayResize(temp, 100);
      if(CopyClose(m_symbols[i], PERIOD_D1, 0, 100, temp) != 100)
        {
         m_synchronizedD1[i] = false;
         continue;
        }
      for(int k = 0; k < 100; k++)
         m_pricesD1[IdxD1(i, k)] = temp[k];
     }

   for(int i = 0; i < m_total; i++)
     {
      for(int j = i+1; j < m_total; j++)
        {
         if(!m_synchronizedD1[i] || !m_synchronizedD1[j])
           {
            m_matrixD1[Idx(i, j)] = 0.0;
            m_matrixD1[Idx(j, i)] = 0.0;
            continue;
           }

         double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0, sumY2 = 0;
         for(int k = 0; k < 100; k++)
           {
            double x = m_pricesD1[IdxD1(i, k)];
            double y = m_pricesD1[IdxD1(j, k)];
            sumX  += x;
            sumY  += y;
            sumXY += x*y;
            sumX2 += x*x;
            sumY2 += y*y;
           }
         double n = 100.0;
         double num = n * sumXY - sumX * sumY;
         double den = MathSqrt((n * sumX2 - sumX*sumX) * (n * sumY2 - sumY*sumY));
         double corr = (den != 0) ? num / den : 0.0;
         m_matrixD1[Idx(i, j)] = corr;
         m_matrixD1[Idx(j, i)] = corr;
        }
     }
   m_updatedD1 = true;
   m_lastUpdateD1 = TimeCurrent();
  }

//+------------------------------------------------------------------+
//| Actualizar matriz M15 (50 barras)                                 |
//+------------------------------------------------------------------+
void CorrelationEngine::UpdateMatrixM15()
  {
   if(m_total < 2)
      return;

   for(int i = 0; i < m_total; i++)
     {
      if(!m_synchronizedM15[i])
         continue;
      double temp[];
      ArrayResize(temp, 50);
      if(CopyClose(m_symbols[i], PERIOD_M15, 0, 50, temp) != 50)
        {
         m_synchronizedM15[i] = false;
         continue;
        }
      for(int k = 0; k < 50; k++)
         m_pricesM15[IdxM15(i, k)] = temp[k];
     }

   for(int i = 0; i < m_total; i++)
     {
      for(int j = i+1; j < m_total; j++)
        {
         if(!m_synchronizedM15[i] || !m_synchronizedM15[j])
           {
            m_matrixM15[Idx(i, j)] = 0.0;
            m_matrixM15[Idx(j, i)] = 0.0;
            continue;
           }

         double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0, sumY2 = 0;
         for(int k = 0; k < 50; k++)
           {
            double x = m_pricesM15[IdxM15(i, k)];
            double y = m_pricesM15[IdxM15(j, k)];
            sumX  += x;
            sumY  += y;
            sumXY += x*y;
            sumX2 += x*x;
            sumY2 += y*y;
           }
         double n = 50.0;
         double num = n * sumXY - sumX * sumY;
         double den = MathSqrt((n * sumX2 - sumX*sumX) * (n * sumY2 - sumY*sumY));
         double corr = (den != 0) ? num / den : 0.0;
         m_matrixM15[Idx(i, j)] = corr;
         m_matrixM15[Idx(j, i)] = corr;
        }
     }
   m_updatedM15 = true;
   m_lastUpdateM15 = TimeCurrent();
  }

//+------------------------------------------------------------------+
//| Actualizar ambas matrices                                         |
//+------------------------------------------------------------------+
void CorrelationEngine::UpdateCorrelationMatrix()
  {
   if(m_total < 2)
      return;

   VerifySynchronization();

   bool forceM15 = false;
   if(TimeCurrent() - m_lastUpdateM15 >= 14400)
      forceM15 = true;

   if(!forceM15)
     {
      double currentATR = CalculatePortfolioATR();
      if(m_lastPortfolioATR > 0 && currentATR > m_lastPortfolioATR * 1.50)
         forceM15 = true;
      m_lastPortfolioATR = currentATR;
     }

   if(TimeCurrent() - m_lastUpdateD1 >= 14400 || !m_updatedD1)
      UpdateMatrixD1();

   if(forceM15 || !m_updatedM15)
      UpdateMatrixM15();

   m_lastAvgSpread = 0.0;
   for(int i = 0; i < m_total; i++)
      if(m_synchronizedM15[i])
         m_lastAvgSpread += (double)SymbolInfoInteger(m_symbols[i], SYMBOL_SPREAD);
   if(m_total > 0)
      m_lastAvgSpread /= m_total;

   m_decouplingCount = 0;
   for(int i = 0; i < m_total; i++)
     {
      for(int j = i+1; j < m_total; j++)
        {
         if(m_updatedD1 && m_updatedM15)
           {
            double corrD1  = MathAbs(m_matrixD1[Idx(i, j)]);
            double corrM15 = MathAbs(m_matrixM15[Idx(i, j)]);
            if(corrD1 > 0.80 && corrM15 < 0.40)
              {
               m_decouplingFlags[Idx(i, j)] = true;
               m_decouplingFlags[Idx(j, i)] = true;
               m_decouplingCount++;
              }
            else
              {
               m_decouplingFlags[Idx(i, j)] = false;
               m_decouplingFlags[Idx(j, i)] = false;
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Buscar índice de un símbolo                                       |
//+------------------------------------------------------------------+
int CorrelationEngine::GetSymbolIndex(string sym)
  {
   for(int i = 0; i < m_total; i++)
      if(m_symbols[i] == sym)
         return i;
   return -1;
  }

//+------------------------------------------------------------------+
//| Correlación D1                                                    |
//+------------------------------------------------------------------+
double CorrelationEngine::GetCorrelation(string sym1, string sym2)
  {
   int idx1 = GetSymbolIndex(sym1);
   int idx2 = GetSymbolIndex(sym2);
   if(idx1 == -1 || idx2 == -1)
      return 0.0;
   return m_matrixD1[Idx(idx1, idx2)];
  }

//+------------------------------------------------------------------+
//| Correlación M15                                                   |
//+------------------------------------------------------------------+
double CorrelationEngine::GetCorrelationM15(string sym1, string sym2)
  {
   int idx1 = GetSymbolIndex(sym1);
   int idx2 = GetSymbolIndex(sym2);
   if(idx1 == -1 || idx2 == -1)
      return 0.0;
   return m_matrixM15[Idx(idx1, idx2)];
  }

//+------------------------------------------------------------------+
//| Desacople institucional                                           |
//+------------------------------------------------------------------+
bool CorrelationEngine::IsFlashDecoupling(string sym1, string sym2)
  {
   int idx1 = GetSymbolIndex(sym1);
   int idx2 = GetSymbolIndex(sym2);
   if(idx1 == -1 || idx2 == -1)
      return false;
   return m_decouplingFlags[Idx(idx1, idx2)];
  }

//+------------------------------------------------------------------+
//| Factor de reducción adaptativo                                    |
//+------------------------------------------------------------------+
double CorrelationEngine::GetAdaptiveReductionFactor(string sym1, string sym2)
  {
   double corrD1  = MathAbs(GetCorrelation(sym1, sym2));
   double corrM15 = MathAbs(GetCorrelationM15(sym1, sym2));
   double combined = corrD1 * 0.30 + corrM15 * 0.70;

   if(IsFlashDecoupling(sym1, sym2))
      combined = MathMin(combined, 0.30);

   double factor;
   if(combined > 0.70)
      factor = 1.0 - (combined - 0.70) * 1.5;
   else
      if(combined < 0.40)
         factor = 1.0;
      else
         factor = 1.0 - (combined - 0.40) * 0.5;

   return MathMax(0.0, MathMin(1.0, factor));
  }

#endif // __CORRELATIONENGINE_MQH__
//+------------------------------------------------------------------+
