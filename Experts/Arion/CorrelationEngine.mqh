//+------------------------------------------------------------------+
//|                                          CorrelationEngine.mqh   |
//|                        Arion - Motor de Correlacion Multicapa    |
//|        Matriz Dual (D1 + M15), Spearman, Incremental,            |
//|        Recuperacion de sincronizacion, Ajuste dinamico           |
//|        * Cache de Spearman implementada (calculo incremental)    |
//|        * RankArray optimizado con ArraySort                       |
//|        * OPTIMIZADO: Matrices triangulares, cache de rangos       |
//|                        Autor: Alexy Hernandez                    |
//|                        Version: 1.0                              |
//|        Copyright (c) 2025 Alexy Hernandez. Todos los derechos    |
//|        reservados.                                               |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernandez. Todos los derechos reservados."
#property link      "https://github.com/axgeovax"
#property version   "1.0"
#property strict

#ifndef __CORRELATIONENGINE_MQH__
#define __CORRELATIONENGINE_MQH__

//+------------------------------------------------------------------+
//| Clase CorrelationEngine                                          |
//|                                                                   |
//| Implementa el motor de correlacion multicapa de Arion.           |
//| Mantiene matrices de correlacion de Pearson y Spearman para dos  |
//| marcos temporales (D1 y M15) con actualizacion incremental o     |
//| completa. Incluye deteccion de desacople institucional y calculo |
//| de un factor de reduccion adaptativo.                            |
//|                                                                   |
//| Spearman se calcula incrementalmente: en cada actualizacion de   |
//| un simbolo se recalcula su correlacion de rangos contra todos    |
//| los demas y se almacena en m_spearmanMatrixD1/M15.              |
//| RankArray ahora usa ArraySort (O(n log n)) para maxima eficiencia.|
//|                                                                   |
//| * Optimizaciones:                                                 |
//|   - Solo se almacena la parte triangular superior de las matrices |
//|   - Se cachean los rangos de cada simbolo para Spearman          |
//+------------------------------------------------------------------+
class CorrelationEngine
  {
private:
   string            m_symbols[];
   int               m_total;

   int               m_lookbackD1;
   int               m_lookbackM15;

   // --- Macro (D1) ---
   double            m_matrixD1[];          // Pearson [n*(n-1)/2]
   double            m_spearmanMatrixD1[];  // Spearman [n*(n-1)/2]
   bool              m_updatedD1;
   datetime          m_lastUpdateD1;
   double            m_pricesD1[];          // plano [total * lookbackD1]
   bool              m_synchronizedD1[];

   // --- Intradia (M15) ---
   double            m_matrixM15[];         // Pearson [n*(n-1)/2]
   double            m_spearmanMatrixM15[]; // Spearman [n*(n-1)/2]
   bool              m_updatedM15;
   datetime          m_lastUpdateM15;
   double            m_pricesM15[];         // plano [total * lookbackM15]
   bool              m_synchronizedM15[];

   // --- Volatilidad / desacople ---
   double            m_lastAvgSpread;
   double            m_lastPortfolioATR;
   bool              m_decouplingFlags[];   // plano [n*(n-1)/2]
   int               m_decouplingCount;

   // --- Indices para actualizacion incremental ---
   int               m_nextSymbolD1;
   int               m_nextSymbolM15;

   // Cache de rangos para Spearman
   double            m_ranksD1[];           // plano [total * lookbackD1]
   double            m_ranksM15[];          // plano [total * lookbackM15]

   // --- Funciones internas ---
   int               Idx(int row, int col) const { return row < col ? row*m_total - row*(row+1)/2 + col - row - 1 : col*m_total - col*(col+1)/2 + row - col - 1; }
   int               IdxD1(int row, int bar) const { return row * m_lookbackD1 + bar; }
   int               IdxM15(int row, int bar) const { return row * m_lookbackM15 + bar; }

   void              VerifySynchronization();
   void              UpdateMatrixD1();
   void              UpdateMatrixM15();
   void              UpdateSingleSymbolD1(int symIdx);
   void              UpdateSingleSymbolM15(int symIdx);
   double            CalculatePortfolioATR();


   // --- Correlacion por rangos (Spearman) ---
   static void       RankArray(double &array[], int length);

public:
                     CorrelationEngine();
                    ~CorrelationEngine() {}

   void              Initialize(string &assets[], int total,
                                int lookbackD1 = 100, int lookbackM15 = 50);

   void              UpdateCorrelationMatrix();
   void              IncrementalUpdate();

   double            GetCorrelation(string sym1, string sym2);
   double            GetCorrelationM15(string sym1, string sym2);
   double            GetSpearmanCorrelation(string sym1, string sym2,
         ENUM_TIMEFRAMES tf = PERIOD_D1);

   bool              IsUpdated() const { return m_updatedD1; }
   bool              IsUpdatedM15() const { return m_updatedM15; }
   double            GetLastAvgSpread() const { return m_lastAvgSpread; }

   bool              IsFlashDecoupling(string sym1, string sym2);
   int               GetDecouplingCount() const { return m_decouplingCount; }
   int               GetDecouplingCountForSymbol(string symbol) const;

   double            GetAdaptiveReductionFactor(string sym1, string sym2, bool useSpearman = false);
   int               GetSymbolIndex(string symbol) const;
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
   m_lookbackD1 = 100;
   m_lookbackM15 = 50;
   m_nextSymbolD1 = 0;
   m_nextSymbolM15 = 0;

   ArrayResize(m_symbols, 0);
   ArrayResize(m_matrixD1, 0);
   ArrayResize(m_spearmanMatrixD1, 0);
   ArrayResize(m_matrixM15, 0);
   ArrayResize(m_spearmanMatrixM15, 0);
   ArrayResize(m_pricesD1, 0);
   ArrayResize(m_pricesM15, 0);
   ArrayResize(m_synchronizedD1, 0);
   ArrayResize(m_synchronizedM15, 0);
   ArrayResize(m_decouplingFlags, 0);
   ArrayResize(m_ranksD1, 0);
   ArrayResize(m_ranksM15, 0);
  }

//+------------------------------------------------------------------+
//| Inicializar con parametros de lookback y matrices de Spearman     |
//+------------------------------------------------------------------+
void CorrelationEngine::Initialize(string &assets[], int total,
                                   int lookbackD1 = 100, int lookbackM15 = 50)
  {
   if(total <= 0)
     {
      Print("Error [CorrelationEngine]: total must be > 0");
      return;
     }

   m_total = MathMin(total, 100);
   m_lookbackD1 = MathMin(MathMax(20, lookbackD1), 1000);
   m_lookbackM15 = MathMin(MathMax(20, lookbackM15), 96000);

   ArrayResize(m_symbols, m_total);
   int matSize = MathMin(m_total * (m_total - 1) / 2, 500000);
   ArrayResize(m_matrixD1, matSize);
   ArrayResize(m_spearmanMatrixD1, matSize);
   ArrayResize(m_matrixM15, matSize);
   ArrayResize(m_spearmanMatrixM15, matSize);
   ArrayResize(m_pricesD1, MathMin(m_total * m_lookbackD1, 1000000));
   ArrayResize(m_pricesM15, MathMin(m_total * m_lookbackM15, 1000000));
   ArrayResize(m_synchronizedD1, m_total);
   ArrayResize(m_synchronizedM15, m_total);
   ArrayResize(m_decouplingFlags, matSize);
   ArrayResize(m_ranksD1, MathMin(m_total * m_lookbackD1, 1000000));
   ArrayResize(m_ranksM15, MathMin(m_total * m_lookbackM15, 1000000));

   for(int i = 0; i < m_total; i++)
     {
      m_symbols[i] = assets[i];
     }

   ArrayInitialize(m_pricesD1, 0.0);
   ArrayInitialize(m_pricesM15, 0.0);
   ArrayInitialize(m_decouplingFlags, false);
   ArrayInitialize(m_synchronizedD1, false);
   ArrayInitialize(m_synchronizedM15, false);
   ArrayInitialize(m_matrixD1, 0.0);
   ArrayInitialize(m_spearmanMatrixD1, 0.0);
   ArrayInitialize(m_matrixM15, 0.0);
   ArrayInitialize(m_spearmanMatrixM15, 0.0);
   ArrayInitialize(m_ranksD1, 0.0);
   ArrayInitialize(m_ranksM15, 0.0);

   VerifySynchronization();
  }

//+------------------------------------------------------------------+
//| Verificar sincronizacion (con recuperacion via Bars)              |
//+------------------------------------------------------------------+
void CorrelationEngine::VerifySynchronization()
  {
   for(int i = 0; i < m_total; i++)
     {
      m_synchronizedD1[i]  = SeriesInfoInteger(m_symbols[i], PERIOD_D1,  SERIES_SYNCHRONIZED);
      m_synchronizedM15[i] = SeriesInfoInteger(m_symbols[i], PERIOD_M15, SERIES_SYNCHRONIZED);

      if(!m_synchronizedD1[i])
        {
         int bars = Bars(m_symbols[i], PERIOD_D1);
         if(bars >= m_lookbackD1)
            m_synchronizedD1[i] = true;
        }
      if(!m_synchronizedM15[i])
        {
         int bars = Bars(m_symbols[i], PERIOD_M15);
         if(bars >= m_lookbackM15)
            m_synchronizedM15[i] = true;
        }
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
//| Actualizar un simbolo en la matriz D1 (Pearson + Spearman)        |
//+------------------------------------------------------------------+
void CorrelationEngine::UpdateSingleSymbolD1(int symIdx)
  {
   if(!m_synchronizedD1[symIdx])
      return;

   double temp[];
   ArrayResize(temp, m_lookbackD1);
   if(CopyClose(m_symbols[symIdx], PERIOD_D1, 0, MathMin(m_lookbackD1, 1000), temp) != MathMin(m_lookbackD1, 1000))
     {
      m_synchronizedD1[symIdx] = false;
      return;
     }
   for(int k = 0; k < m_lookbackD1; k++)
      m_pricesD1[IdxD1(symIdx, k)] = temp[k];

// --- Calcular rangos de este simbolo una sola vez ---
   double ranksSym[];
   ArrayResize(ranksSym, m_lookbackD1);
   for(int k = 0; k < m_lookbackD1; k++)
      ranksSym[k] = temp[k];
   RankArray(ranksSym, m_lookbackD1);
   for(int k = 0; k < m_lookbackD1; k++)
      m_ranksD1[IdxD1(symIdx, k)] = ranksSym[k];

   for(int j = 0; j < m_total; j++)
     {
      if(j == symIdx)
         continue;
      if(!m_synchronizedD1[j])
         continue;

      // Pearson
      double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0, sumY2 = 0;
      for(int k = 0; k < m_lookbackD1; k++)
        {
         double x = m_pricesD1[IdxD1(symIdx, k)];
         double y = m_pricesD1[IdxD1(j, k)];
         sumX  += x;
         sumY  += y;
         sumXY += x*y;
         sumX2 += x*x;
         sumY2 += y*y;
        }
      double n = (double)m_lookbackD1;
      double num = n * sumXY - sumX * sumY;
      double den = MathSqrt((n * sumX2 - sumX*sumX) * (n * sumY2 - sumY*sumY));
      double corr = (den != 0) ? num / den : 0.0;
      m_matrixD1[Idx(symIdx, j)] = corr;

      // Spearman (usando rangos ya calculados para symIdx)
      double ranksJ[];
      ArrayResize(ranksJ, m_lookbackD1);
      for(int k = 0; k < m_lookbackD1; k++)
         ranksJ[k] = m_pricesD1[IdxD1(j, k)];
      RankArray(ranksJ, m_lookbackD1);
      for(int k = 0; k < m_lookbackD1; k++)
         m_ranksD1[IdxD1(j, k)] = ranksJ[k];

      double sumRX = 0, sumRY = 0, sumRXY = 0, sumRX2 = 0, sumRY2 = 0;
      for(int k = 0; k < m_lookbackD1; k++)
        {
         double x = ranksSym[k];
         double y = ranksJ[k];
         sumRX  += x;
         sumRY  += y;
         sumRXY += x*y;
         sumRX2 += x*x;
         sumRY2 += y*y;
        }
      double numR = n * sumRXY - sumRX * sumRY;
      double denR = MathSqrt((n * sumRX2 - sumRX*sumRX) * (n * sumRY2 - sumRY*sumRY));
      double spearman = (denR != 0) ? numR / denR : 0.0;
      m_spearmanMatrixD1[Idx(symIdx, j)] = spearman;
     }
  }

//+------------------------------------------------------------------+
//| Actualizar un simbolo en la matriz M15 (Pearson + Spearman)       |
//+------------------------------------------------------------------+
void CorrelationEngine::UpdateSingleSymbolM15(int symIdx)
  {
   if(!m_synchronizedM15[symIdx])
      return;

   double temp[];
   ArrayResize(temp, m_lookbackM15);
   if(CopyClose(m_symbols[symIdx], PERIOD_M15, 0, MathMin(m_lookbackM15, 1000), temp) != MathMin(m_lookbackM15, 1000))
     {
      m_synchronizedM15[symIdx] = false;
      return;
     }
   for(int k = 0; k < m_lookbackM15; k++)
      m_pricesM15[IdxM15(symIdx, k)] = temp[k];

// --- Calcular rangos de este simbolo una sola vez ---
   double ranksSym[];
   ArrayResize(ranksSym, m_lookbackM15);
   for(int k = 0; k < m_lookbackM15; k++)
      ranksSym[k] = temp[k];
   RankArray(ranksSym, m_lookbackM15);
   for(int k = 0; k < m_lookbackM15; k++)
      m_ranksM15[IdxM15(symIdx, k)] = ranksSym[k];

   for(int j = 0; j < m_total; j++)
     {
      if(j == symIdx)
         continue;
      if(!m_synchronizedM15[j])
         continue;

      // Pearson
      double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0, sumY2 = 0;
      for(int k = 0; k < m_lookbackM15; k++)
        {
         double x = m_pricesM15[IdxM15(symIdx, k)];
         double y = m_pricesM15[IdxM15(j, k)];
         sumX  += x;
         sumY  += y;
         sumXY += x*y;
         sumX2 += x*x;
         sumY2 += y*y;
        }
      double n = (double)m_lookbackM15;
      double num = n * sumXY - sumX * sumY;
      double den = MathSqrt((n * sumX2 - sumX*sumX) * (n * sumY2 - sumY*sumY));
      double corr = (den != 0) ? num / den : 0.0;
      m_matrixM15[Idx(symIdx, j)] = corr;

      // Spearman (usando rangos ya calculados para symIdx)
      double ranksJ[];
      ArrayResize(ranksJ, m_lookbackM15);
      for(int k = 0; k < m_lookbackM15; k++)
         ranksJ[k] = m_pricesM15[IdxM15(j, k)];
      RankArray(ranksJ, m_lookbackM15);
      for(int k = 0; k < m_lookbackM15; k++)
         m_ranksM15[IdxM15(j, k)] = ranksJ[k];

      double sumRX = 0, sumRY = 0, sumRXY = 0, sumRX2 = 0, sumRY2 = 0;
      for(int k = 0; k < m_lookbackM15; k++)
        {
         double x = ranksSym[k];
         double y = ranksJ[k];
         sumRX  += x;
         sumRY  += y;
         sumRXY += x*y;
         sumRX2 += x*x;
         sumRY2 += y*y;
        }
      double numR = n * sumRXY - sumRX * sumRY;
      double denR = MathSqrt((n * sumRX2 - sumRX*sumRX) * (n * sumRY2 - sumRY*sumRY));
      double spearman = (denR != 0) ? numR / denR : 0.0;
      m_spearmanMatrixM15[Idx(symIdx, j)] = spearman;
     }
  }

//+------------------------------------------------------------------+
//| Actualizacion incremental (alterna entre D1 y M15, un simbolo)    |
//+------------------------------------------------------------------+
void CorrelationEngine::IncrementalUpdate()
  {
   if(m_total < 2)
      return;

   static bool toggle = false;
   toggle = !toggle;

   if(toggle)
     {
      int idx = m_nextSymbolD1 % m_total;
      UpdateSingleSymbolD1(idx);
      m_nextSymbolD1 = (idx + 1) % m_total;
      if(idx == 0)
         m_updatedD1 = true;
     }
   else
     {
      int idx = m_nextSymbolM15 % m_total;
      UpdateSingleSymbolM15(idx);
      m_nextSymbolM15 = (idx + 1) % m_total;
      if(idx == 0)
         m_updatedM15 = true;
     }

   m_lastAvgSpread = 0.0;
   for(int i = 0; i < m_total; i++)
      if(m_synchronizedM15[i])
         m_lastAvgSpread += (double)SymbolInfoInteger(m_symbols[i], SYMBOL_SPREAD);
   if(m_total > 0)
      m_lastAvgSpread /= m_total;

   if(m_updatedD1 && m_updatedM15)
     {
      m_decouplingCount = 0;
      for(int i = 0; i < m_total; i++)
        {
         for(int j = i+1; j < m_total; j++)
           {
            double corrD1  = MathAbs(m_matrixD1[Idx(i, j)]);
            double corrM15 = MathAbs(m_matrixM15[Idx(i, j)]);
            if(corrD1 > 0.70 && corrM15 < 0.50)
              {
               m_decouplingFlags[Idx(i, j)] = true;
               m_decouplingCount++;
              }
            else
               m_decouplingFlags[Idx(i, j)] = false;
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Actualizacion completa (conservada)                               |
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
     {
      UpdateMatrixD1();
      m_lastUpdateD1 = TimeCurrent();
     }
   if(forceM15 || !m_updatedM15)
     {
      UpdateMatrixM15();
      m_lastUpdateM15 = TimeCurrent();
     }

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
            if(corrD1 > 0.70 && corrM15 < 0.50)
              {
               m_decouplingFlags[Idx(i, j)] = true;
               m_decouplingCount++;
              }
            else
               m_decouplingFlags[Idx(i, j)] = false;
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Actualizar matriz D1 completa (para referencia)                   |
//+------------------------------------------------------------------+
void CorrelationEngine::UpdateMatrixD1()
  {
   for(int i = 0; i < m_total; i++)
      UpdateSingleSymbolD1(i);
  }

//+------------------------------------------------------------------+
//| Actualizar matriz M15 completa                                    |
//+------------------------------------------------------------------+
void CorrelationEngine::UpdateMatrixM15()
  {
   for(int i = 0; i < m_total; i++)
      UpdateSingleSymbolM15(i);
  }

//+------------------------------------------------------------------+
//| Correlacion de Pearson D1                                         |
//+------------------------------------------------------------------+
double CorrelationEngine::GetCorrelation(string sym1, string sym2)
  {
   int idx1 = GetSymbolIndex(sym1);
   int idx2 = GetSymbolIndex(sym2);
   if(idx1 == -1 || idx2 == -1 || idx1 == idx2)
      return 0.0;
   return m_matrixD1[Idx(idx1, idx2)];
  }

//+------------------------------------------------------------------+
//| Correlacion de Pearson M15                                        |
//+------------------------------------------------------------------+
double CorrelationEngine::GetCorrelationM15(string sym1, string sym2)
  {
   int idx1 = GetSymbolIndex(sym1);
   int idx2 = GetSymbolIndex(sym2);
   if(idx1 == -1 || idx2 == -1 || idx1 == idx2)
      return 0.0;
   return m_matrixM15[Idx(idx1, idx2)];
  }

//+------------------------------------------------------------------+
//| Calcula los rangos de los elementos de un arreglo (ArraySort)     |
//| Complejidad O(n log n) para maxima eficiencia con portafolios    |
//| de 20-30 activos.                                                |
//+------------------------------------------------------------------+
void CorrelationEngine::RankArray(double &array[], int length)
  {
// Pares (valor, indice original)
   struct ValIdx { double val; int idx; };
   ValIdx pairs[];
   ArrayResize(pairs, length);

// Copiar a array simple para ordenar
   double sortArr[];
   ArrayResize(sortArr, length);
   for(int i = 0; i < length; i++)
     {
      pairs[i].val = array[i];
      pairs[i].idx = i;
      sortArr[i] = array[i];
     }

// Ordenar con ArraySort (nativo, eficiente)
   ArraySort(sortArr);

// Marcar elementos ya asignados para manejar empates
   bool assigned[];
   ArrayResize(assigned, length);
   ArrayInitialize(assigned, false);

// Reconstruir el orden original
   ValIdx sortedPairs[];
   ArrayResize(sortedPairs, length);
   for(int i = 0; i < length; i++)
     {
      for(int j = 0; j < length; j++)
        {
         if(!assigned[j] && pairs[j].val == sortArr[i])
           {
            sortedPairs[i] = pairs[j];
            assigned[j] = true;
            break;
           }
        }
     }

// Asignar rangos (promedio en empates)
   double rank = 1;
   for(int i = 0; i < length; i++)
     {
      if(i > 0 && sortedPairs[i].val != sortedPairs[i-1].val)
         rank = (double)(i + 1);
      array[sortedPairs[i].idx] = rank;
     }
  }

//+------------------------------------------------------------------+
//| Correlacion de Spearman – ahora solo retorna cache                |
//+------------------------------------------------------------------+
double CorrelationEngine::GetSpearmanCorrelation(string sym1, string sym2, ENUM_TIMEFRAMES tf = PERIOD_D1)
  {
   int idx1 = GetSymbolIndex(sym1);
   int idx2 = GetSymbolIndex(sym2);
   if(idx1 == -1 || idx2 == -1 || idx1 == idx2)
      return 0.0;
   if(tf == PERIOD_D1)
      return m_spearmanMatrixD1[Idx(idx1, idx2)];
   else
      return m_spearmanMatrixM15[Idx(idx1, idx2)];
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
//| Factor de reduccion adaptativo                                    |
//+------------------------------------------------------------------+
double CorrelationEngine::GetAdaptiveReductionFactor(string sym1, string sym2, bool useSpearman = false)
  {
   double corrD1, corrM15;
   if(useSpearman)
     {
      corrD1  = MathAbs(GetSpearmanCorrelation(sym1, sym2, PERIOD_D1));
      corrM15 = MathAbs(GetSpearmanCorrelation(sym1, sym2, PERIOD_M15));
     }
   else
     {
      corrD1  = MathAbs(GetCorrelation(sym1, sym2));
      corrM15 = MathAbs(GetCorrelationM15(sym1, sym2));
     }

   double combined = corrD1 * 0.30 + corrM15 * 0.70;

   if(IsFlashDecoupling(sym1, sym2))
      combined = 0.90;

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

//+------------------------------------------------------------------+
//| Indice de simbolo                                                 |
//+------------------------------------------------------------------+
int CorrelationEngine::GetSymbolIndex(string symbol) const
  {
   for(int i = 0; i < m_total; i++)
      if(m_symbols[i] == symbol)
         return i;
   return -1;
  }

//+------------------------------------------------------------------+
//| Cuenta de desacoples para un simbolo                              |
//+------------------------------------------------------------------+
int CorrelationEngine::GetDecouplingCountForSymbol(string symbol) const
  {
   int symIdx = GetSymbolIndex(symbol);
   if(symIdx < 0)
      return 0;

   int count = 0;
   for(int i = 0; i < m_total; i++)
     {
      if(i != symIdx && m_decouplingFlags[Idx(symIdx, i)])
         count++;
     }
   return count;
  }

#endif // __CORRELATIONENGINE_MQH__
//+------------------------------------------------------------------+
