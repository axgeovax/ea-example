//+------------------------------------------------------------------+
//|                                               SignalFilter.mqh   |
//|                        Arion - Filtro Adaptativo v1.0              |
//|          * DINAMICO SIN SESGOS: concordancia modulada por        |
//|            correlacion real ONNX-KNN (Spearman).                  |
//|                        Autor: Alexy Hernandez                    |
//|                        Version: 1.0                              |
//|        Copyright (c) 2025 Alexy Hernandez. Todos los derechos    |
//|        reservados.                                               |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernandez. Todos los derechos reservados."
#property link      "https://github.com/axgeovax"
#property version   "1.0"
#property strict

#ifndef __SIGNALFILTER_MQH__
#define __SIGNALFILTER_MQH__

#define HISTORY_SIZE 50   // muestras para correlacion dinamica

enum ENUM_SIGNAL_STATE
  {
   SIGNAL_STATE_SEARCHING,
   SIGNAL_STATE_IN_POSITION,
   SIGNAL_STATE_RETRY_WAIT
  };

struct SignalBreakdown
  {
   double            scoreONNX;
   double            scoreKNN;
   double            scoreSMC;
   double            scoreContext;
   double            scoreAI;
   double            concordanceFactor;
   double            weightONNX;
   double            weightKNN;
   double            weightSMC;
   double            weightContext;
   double            totalScore;
   double            correlation;       // correlacion reciente ONNX-KNN
   string            errorMessage;
  };

//+------------------------------------------------------------------+
//| Clase SignalFilter                                                |
//+------------------------------------------------------------------+
class SignalFilter
  {
private:
   string            m_symbol;
   ENUM_SIGNAL_STATE m_state;
   bool              m_cooldownEnabled;
   int               m_lossCooldownBars;
   datetime          m_lockoutUntil;
   bool              m_orderInFlight;

   // Historial circular para correlacion dinamica
   double            m_historyONNX[HISTORY_SIZE];
   double            m_historyKNN[HISTORY_SIZE];
   int               m_historyIndex;
   int               m_historyCount;

   double            NormalizeKNNProbability(double probKNN);          // lineal pura
   double            ComputeSpearmanCorrelation();                     // correlacion real
   void              PushToHistory(double onnx, double knn);

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
   SignalBreakdown   GetSignalBreakdown(int macroDirection,
                                        double probONNX,
                                        double probKNN,
                                        bool zoneMitigated,
                                        double mitigationRatio,
                                        double relativeVolatility,
                                        long spread = -1);

   void              SetLossCooldownBars(int bars) { m_lossCooldownBars = MathMax(0, bars); }
   void              EnableCooldown(bool enable)   { m_cooldownEnabled = enable; }

   void              OnPositionOpened();
   void              OnPositionClosed(double profit);
   void              OnNewBar();
   ENUM_SIGNAL_STATE GetState() const { return m_state; }
   void              SetOrderInFlight(bool inFlight) { m_orderInFlight = inFlight; }
  };

//+------------------------------------------------------------------+
//| Constructor                                                        |
//+------------------------------------------------------------------+
SignalFilter::SignalFilter(string symbol)
  {
   m_symbol = (symbol == NULL) ? _Symbol : symbol;
   m_state = SIGNAL_STATE_SEARCHING;
   m_cooldownEnabled = true;
   m_lossCooldownBars = 5;
   m_lockoutUntil = 0;
   m_orderInFlight = false;

   ArrayInitialize(m_historyONNX, 0.0);
   ArrayInitialize(m_historyKNN, 0.0);
   m_historyIndex = 0;
   m_historyCount = 0;
  }

//+------------------------------------------------------------------+
//| Normalizacion KNN: lineal pura de [-1,1] a [0,1]                  |
//+------------------------------------------------------------------+
double SignalFilter::NormalizeKNNProbability(double probKNN)
  {
   double result = (probKNN + 1.0) / 2.0;
   return MathMax(0.0, MathMin(1.0, result));
  }

//+------------------------------------------------------------------+
//| Almacena una nueva observacion en el historial circular           |
//+------------------------------------------------------------------+
void SignalFilter::PushToHistory(double onnx, double knn)
  {
   m_historyONNX[m_historyIndex] = onnx;
   m_historyKNN[m_historyIndex] = knn;
   m_historyIndex = (m_historyIndex + 1) % HISTORY_SIZE;
   if(m_historyCount < HISTORY_SIZE)
      m_historyCount++;
  }

//+------------------------------------------------------------------+
//| Calcula la correlacion de Spearman entre las ultimas muestras     |
//| de ONNX y KNN (valores reales, sin sesgo).                        |
//+------------------------------------------------------------------+
double SignalFilter::ComputeSpearmanCorrelation()
  {
   if(m_historyCount < 10)
      return 0.0;   // insuficientes datos

// Copiar a arrays locales para ordenar
   double onnxVals[], knnVals[];
   ArrayResize(onnxVals, m_historyCount);
   ArrayResize(knnVals, m_historyCount);
   for(int i = 0; i < m_historyCount; i++)
     {
      onnxVals[i] = m_historyONNX[i];
      knnVals[i] = m_historyKNN[i];
     }

// Calcular rangos de Spearman para ONNX
   double rankONNX[];
   ArrayResize(rankONNX, m_historyCount);
   for(int i = 0; i < m_historyCount; i++)
     {
      double val = onnxVals[i];
      int rank = 1;
      for(int j = 0; j < m_historyCount; j++)
         if(onnxVals[j] < val)
            rank++;
      rankONNX[i] = rank;
     }

// Calcular rangos de Spearman para KNN
   double rankKNN[];
   ArrayResize(rankKNN, m_historyCount);
   for(int i = 0; i < m_historyCount; i++)
     {
      double val = knnVals[i];
      int rank = 1;
      for(int j = 0; j < m_historyCount; j++)
         if(knnVals[j] < val)
            rank++;
      rankKNN[i] = rank;
     }

// Coeficiente de correlacion de Spearman
   double sumD2 = 0.0;
   for(int i = 0; i < m_historyCount; i++)
     {
      double d = rankONNX[i] - rankKNN[i];
      sumD2 += d * d;
     }

   double n = (double)m_historyCount;
   double rho = 1.0 - (6.0 * sumD2) / (n * (n * n - 1.0));

   return MathMax(-1.0, MathMin(1.0, rho));
  }

//+------------------------------------------------------------------+
//| Procesa una senal con dinamicidad basada en correlacion real     |
//+------------------------------------------------------------------+
double SignalFilter::ProcessSignal(int macroDirection,
                                   double probONNX,
                                   double probKNN,
                                   bool zoneMitigated,
                                   double mitigationRatio,
                                   double relativeVolatility)
  {
   if(m_cooldownEnabled && TimeCurrent() < m_lockoutUntil)
      return 0.0;
   if(m_state != SIGNAL_STATE_SEARCHING)
      return 0.0;
   if(m_orderInFlight)
      return 0.0;

// Almacenar en historial para futura correlacion
   PushToHistory(probONNX, probKNN);

   double weightONNX     = InpWeightONNX;
   double weightKNN      = InpWeightKNN;
   double weightSMC      = InpWeightSMC;
   double weightContext  = InpWeightContext;

   double scoreONNX = probONNX * weightONNX;
   double probKNNNorm = NormalizeKNNProbability(probKNN);
   double scoreKNN = probKNNNorm * weightKNN;

   double safeRatio = MathMax(0.0, MathMin(1.0, mitigationRatio));
   double scoreSMC = zoneMitigated ? safeRatio * weightSMC : 0.0;
   double scoreContext = weightContext;   // constante, sin umbrales

// Concordancia base
   double rawConcordance = 1.0 - MathAbs(probONNX - probKNNNorm);

// ---- MODULACION DINAMICA SIN SESGO ----
   double rho = ComputeSpearmanCorrelation();
   double dynamicFactor;
   if(rho >= 0.7)
      dynamicFactor = 1.0 + 0.2 * (rho - 0.7) / 0.3;   // max 1.2
   else
      if(rho < 0.3)
         dynamicFactor = 0.5 + 0.5 * rho / 0.3;           // min 0.5
      else
         dynamicFactor = 1.0;

   double finalConcordance = rawConcordance * dynamicFactor;
   finalConcordance = MathMax(0.0, MathMin(1.2, finalConcordance));

   double scoreAI = (scoreONNX + scoreKNN) * finalConcordance;

   return scoreAI + scoreSMC + scoreContext;
  }

//+------------------------------------------------------------------+
//| Filtros duros previos a la entrada                                 |
//+------------------------------------------------------------------+
bool SignalFilter::PassHardFilters(long spread, int maxTrades)
  {
   if(m_cooldownEnabled && TimeCurrent() < m_lockoutUntil)
      return false;
   if(spread > InpMaxSpreadPoints)
      return false;
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
     {
      if(PositionSelectByTicket(PositionGetTicket(i)))
         if(PositionGetString(POSITION_SYMBOL) == m_symbol)
            count++;
     }
   return (count < maxTrades);
  }

//+------------------------------------------------------------------+
//| Desglose detallado de la senal                                     |
//+------------------------------------------------------------------+
SignalBreakdown SignalFilter::GetSignalBreakdown(int macroDirection,
      double probONNX,
      double probKNN,
      bool zoneMitigated,
      double mitigationRatio,
      double relativeVolatility,
      long spread)
  {
   SignalBreakdown result;
   ZeroMemory(result);

   if(m_cooldownEnabled && TimeCurrent() < m_lockoutUntil)
     {
      result.totalScore = 0.0;
      result.errorMessage = "Cooldown active";
      return result;
     }
   if(spread > 0 && spread > InpMaxSpreadPoints)
     {
      result.totalScore = 0.0;
      result.errorMessage = "Spread too high";
      return result;
     }
   if(macroDirection == 0)
     {
      result.totalScore = 0.0;
      result.errorMessage = "Neutral direction";
      return result;
     }

   result.weightONNX    = InpWeightONNX;
   result.weightKNN     = InpWeightKNN;
   result.weightSMC     = InpWeightSMC;
   result.weightContext = InpWeightContext;

   result.scoreONNX = probONNX * result.weightONNX;
   double probKNNNorm = NormalizeKNNProbability(probKNN);
   result.scoreKNN = probKNNNorm * result.weightKNN;
   result.scoreSMC = zoneMitigated ? mitigationRatio * result.weightSMC : 0.0;
   result.scoreContext = result.weightContext;

   double rawConcordance = 1.0 - MathAbs(probONNX - probKNNNorm);

// Obtener correlacion reciente
   double rho = ComputeSpearmanCorrelation();
   double dynamicFactor;
   if(rho >= 0.7)
      dynamicFactor = 1.0 + 0.2 * (rho - 0.7) / 0.3;
   else
      if(rho < 0.3)
         dynamicFactor = 0.5 + 0.5 * rho / 0.3;
      else
         dynamicFactor = 1.0;

   result.concordanceFactor = rawConcordance * dynamicFactor;
   result.correlation = rho;
   result.scoreAI = (result.scoreONNX + result.scoreKNN) * result.concordanceFactor;
   result.totalScore = result.scoreAI + result.scoreSMC + result.scoreContext;

   return result;
  }

//+------------------------------------------------------------------+
//| Eventos de trading                                                |
//+------------------------------------------------------------------+
void SignalFilter::OnPositionOpened()
  {
   m_state = SIGNAL_STATE_IN_POSITION;
   m_orderInFlight = false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SignalFilter::OnPositionClosed(double profit)
  {
   if(profit < 0 && m_cooldownEnabled)
     {
      m_lockoutUntil = TimeCurrent() + (m_lossCooldownBars * 900);
      m_state = SIGNAL_STATE_RETRY_WAIT;
     }
   else
      m_state = SIGNAL_STATE_SEARCHING;
   m_orderInFlight = false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SignalFilter::OnNewBar()
  {
   if(m_state == SIGNAL_STATE_RETRY_WAIT && m_cooldownEnabled)
      if(TimeCurrent() >= m_lockoutUntil)
         m_state = SIGNAL_STATE_SEARCHING;
  }

#endif // __SIGNALFILTER_MQH__
//+------------------------------------------------------------------+
