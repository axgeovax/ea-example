//+------------------------------------------------------------------+
//|                                       TrainingLabelGenerator.mqh |
//|                   Generador de etiquetas reales para KNN         |
//|                        Autor: Alexy Hernandez                    |
//|                        Version: 1.0                              |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernandez. Todos los derechos reservados."
#property version   "1.0"
#property strict

#ifndef __TRAININGLABELGENERATOR_MQH__
#define __TRAININGLABELGENERATOR_MQH__

#define FUTURE_BARS 20
#define PERCENTILE_BUFFER 1000

class TrainingLabelGenerator
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;
   int               m_futureBars;

   double            m_returnBuffer[PERCENTILE_BUFFER];
   int               m_bufferCount;
   int               m_bufferIdx;

   struct PendingBar
     {
      datetime         time;
      double           close;
      double           features[];      // array dinámico
     };
   PendingBar        m_pending[];
   int               m_pendingCount;

   double            m_P20, m_P40, m_P60, m_P80;
   bool              m_percentilesReady;

   void              UpdatePercentiles();
   double            GetLabelForReturnInternal(double futureReturn);

public:
                     TrainingLabelGenerator(string symbol = NULL, ENUM_TIMEFRAMES tf = PERIOD_M15);
                    ~TrainingLabelGenerator() {}

   bool              Initialize(int futureBars = FUTURE_BARS);

   // 'features' pasado por referencia como array dinámico
   void              OnNewBar(double close, double &features[]);

   bool              IsReady() const { return m_pendingCount > m_futureBars; }
   double            GetLabel();

   // 'features' devuelto por referencia como array dinámico
   bool              GetFeatures(double &features[]);
   void              ConsumeOldest();

   double            GetLabelForReturn(double futureReturn);
  };

//+------------------------------------------------------------------+
//| Constructor                                                        |
//+------------------------------------------------------------------+
TrainingLabelGenerator::TrainingLabelGenerator(string symbol, ENUM_TIMEFRAMES tf)
  {
   m_symbol = (symbol == NULL) ? _Symbol : symbol;
   m_timeframe = tf;
   m_futureBars = FUTURE_BARS;
   m_bufferCount = 0;
   m_bufferIdx = 0;
   m_pendingCount = 0;
   m_percentilesReady = false;
   ArrayResize(m_pending, 0);
  }

bool TrainingLabelGenerator::Initialize(int futureBars = FUTURE_BARS)
  {
   m_futureBars = futureBars;
   return true;
  }

void TrainingLabelGenerator::UpdatePercentiles()
  {
   if(m_bufferCount < 100) return;

   double sorted[];
   ArrayResize(sorted, m_bufferCount);
   for(int i = 0; i < m_bufferCount; i++)
      sorted[i] = m_returnBuffer[i];
   ArraySort(sorted);

   int idx20 = (int)MathRound(m_bufferCount * 0.20) - 1;
   int idx40 = (int)MathRound(m_bufferCount * 0.40) - 1;
   int idx60 = (int)MathRound(m_bufferCount * 0.60) - 1;
   int idx80 = (int)MathRound(m_bufferCount * 0.80) - 1;
   if(idx20 < 0) idx20 = 0;
   if(idx40 < 0) idx40 = 0;
   if(idx60 < 0) idx60 = 0;
   if(idx80 < 0) idx80 = 0;

   m_P20 = sorted[idx20];
   m_P40 = sorted[idx40];
   m_P60 = sorted[idx60];
   m_P80 = sorted[idx80];
   m_percentilesReady = true;
  }

double TrainingLabelGenerator::GetLabelForReturnInternal(double futureReturn)
  {
   if(!m_percentilesReady) return 0.0;

   if(futureReturn <= m_P20)      return -1.0;
   else if(futureReturn <= m_P40) return -0.5;
   else if(futureReturn <= m_P60) return  0.0;
   else if(futureReturn <= m_P80) return  0.5;
   else                           return  1.0;
  }

void TrainingLabelGenerator::OnNewBar(double close, double &features[])
  {
   // Añadir esta vela al final de la cola
   PendingBar bar;
   bar.time = TimeCurrent();
   bar.close = close;
   ArrayResize(bar.features, 12);
   for(int i = 0; i < 12; i++)
      bar.features[i] = features[i];

   int idx = m_pendingCount;
   m_pendingCount++;
   ArrayResize(m_pending, m_pendingCount);
   m_pending[idx] = bar;

   // Si ya tenemos suficientes barras para el futuro
   if(m_pendingCount > m_futureBars)
     {
      double currentClose = m_pending[0].close;
      double futureClose  = m_pending[m_futureBars].close;
      double futureReturn = (futureClose - currentClose) / currentClose;

      m_returnBuffer[m_bufferIdx] = futureReturn;
      m_bufferIdx = (m_bufferIdx + 1) % PERCENTILE_BUFFER;
      if(m_bufferCount < PERCENTILE_BUFFER)
         m_bufferCount++;

      UpdatePercentiles();
     }
  }

double TrainingLabelGenerator::GetLabel()
  {
   if(m_pendingCount <= m_futureBars) return 0.0;

   double currentClose = m_pending[0].close;
   double futureClose  = m_pending[m_futureBars].close;
   double futureReturn = (futureClose - currentClose) / currentClose;
   return GetLabelForReturnInternal(futureReturn);
  }

bool TrainingLabelGenerator::GetFeatures(double &features[])
  {
   if(m_pendingCount == 0) return false;
   ArrayResize(features, 12);
   for(int i = 0; i < 12; i++)
      features[i] = m_pending[0].features[i];
   return true;
  }

void TrainingLabelGenerator::ConsumeOldest()
  {
   if(m_pendingCount == 0) return;
   for(int i = 0; i < m_pendingCount - 1; i++)
      m_pending[i] = m_pending[i + 1];
   m_pendingCount--;
   ArrayResize(m_pending, m_pendingCount);
  }

double TrainingLabelGenerator::GetLabelForReturn(double futureReturn)
  {
   if(!m_percentilesReady) return 0.0;
   return GetLabelForReturnInternal(futureReturn);
  }

#endif // __TRAININGLABELGENERATOR_MQH__