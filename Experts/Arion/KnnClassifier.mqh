//+------------------------------------------------------------------+
//|                                               KnnClassifier.mqh  |
//|                        Arion - KNN 12D normalizado               |
//|                        Autor: Alexy Hernández                    |
//|                        Versión: 1.0                              |
//|        Copyright (c) 2025 Alexy Hernández. Todos los derechos    |
//|        reservados.                                               |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernández. Todos los derechos reservados."
#property link      "https://github.com/axgeovax"
#property version   "1.0"
#property strict

#ifndef __KNNCLASSIFIER_MQH__
#define __KNNCLASSIFIER_MQH__

#define KNN_DIM 12   // dimensiones del vector de características

struct KnnSample
  {
   double            slope, atr, momentum, volFlow, adx, rsi;       // originales
   double            deltaVol, spreadDev, smcRatio, relStrength;     // nuevas
   double            normVolatility, volRatio;                       // completan 12
   int               direction;
   datetime          time;
  };

struct DistDir { double dist; int dir; };

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class KnnClassifier
  {
private:
   KnnSample         m_samples[];
   int               m_capacity, m_total, m_insertIndex;
   double            m_lambda;
   double            m_mean[KNN_DIM];
   double            m_m2[KNN_DIM];
   int               m_countStats;

   void              UpdateStatistics(const KnnSample &sample);
   double            NormalizeDifference(double diff, int dimension) const;
   int               m_samplesSinceSave;  // muestras añadidas desde el último guardado
   bool              m_autoSavePending;   // true si se alcanzó el umbral

public:
                     KnnClassifier(int capacity = 500, double lambda = 0.002);
                    ~KnnClassifier() {}

   void              AddSample(double slope, double atr, double momentum, double volFlow,
                               double adx, double rsi, int direction,
                               double deltaVol = 0.0, double spreadDev = 0.0,
                               double smcRatio = 0.0, double relStrength = 0.0,
                               double normVolatility = 0.0, double volRatio = 1.0);

   double            CalculateKNNProbability(double slope, double atr, double momentum, double volFlow,
         double adx, double rsi,
         double deltaVol = 0.0, double spreadDev = 0.0,
         double smcRatio = 0.0, double relStrength = 0.0,
         double normVolatility = 0.0, double volRatio = 1.0,
         int kNeighbors = 15) const;

   bool              SaveState(string fileName);
   bool              LoadState(string fileName);
   bool              ExportSamplesToCSV(string fileName);
   bool              IsAutoSavePending() const { return m_autoSavePending; }
   void              ResetAutoSaveFlag() { m_autoSavePending = false; m_samplesSinceSave = 0; }
  };

// Constructor
KnnClassifier::KnnClassifier(int capacity, double lambda)
  {
   m_capacity = MathMax(1, capacity);
   ArrayResize(m_samples, m_capacity);
   m_total = 0;
   m_insertIndex = 0;
   m_lambda = lambda;
   ArrayInitialize(m_mean, 0.0);
   ArrayInitialize(m_m2, 0.0);
   m_countStats = 0;
   m_samplesSinceSave = 0;
   m_autoSavePending = false;
  }

//+------------------------------------------------------------------+
//| Actualizar estadísticas online (Welford) – 12 dimensiones         |
//+------------------------------------------------------------------+
void KnnClassifier::UpdateStatistics(const KnnSample &sample)
  {
   double val[KNN_DIM] =
     {
      sample.slope, sample.atr, sample.momentum, sample.volFlow,
      sample.adx, sample.rsi, sample.deltaVol, sample.spreadDev,
      sample.smcRatio, sample.relStrength, sample.normVolatility, sample.volRatio
     };
   m_countStats++;
   for(int d = 0; d < KNN_DIM; d++)
     {
      double delta = val[d] - m_mean[d];
      m_mean[d] += delta / m_countStats;
      double delta2 = val[d] - m_mean[d];
      m_m2[d] += delta * delta2;
     }
  }

//+------------------------------------------------------------------+
//| Normalizar diferencia                                              |
//+------------------------------------------------------------------+
double KnnClassifier::NormalizeDifference(double diff, int dimension) const
  {
   if(m_countStats < 2)
      return diff;
   double variance = m_m2[dimension] / (m_countStats - 1);
   double std = MathSqrt(variance);
   if(std < 1e-12)
      return diff;
   return diff / std;
  }

//+------------------------------------------------------------------+
//| Agregar muestra (12 parámetros)                                    |
//+------------------------------------------------------------------+
void KnnClassifier::AddSample(double slope, double atr, double momentum, double volFlow,
                              double adx, double rsi, int direction,
                              double deltaVol, double spreadDev,
                              double smcRatio, double relStrength,
                              double normVolatility, double volRatio)
  {
   if(m_insertIndex >= m_capacity)
      m_insertIndex = 0;
   KnnSample sample;
   sample.slope = slope;
   sample.atr = atr;
   sample.momentum = momentum;
   sample.volFlow = volFlow;
   sample.adx = adx;
   sample.rsi = rsi;
   sample.deltaVol = deltaVol;
   sample.spreadDev = spreadDev;
   sample.smcRatio = smcRatio;
   sample.relStrength = relStrength;
   sample.normVolatility = normVolatility;
   sample.volRatio = volRatio;
   sample.direction = direction;
   sample.time = TimeCurrent();

   m_samples[m_insertIndex] = sample;
   m_insertIndex++;
   if(m_total < m_capacity)
      m_total++;
   UpdateStatistics(sample);
   m_samplesSinceSave++;
   if(m_samplesSinceSave >= 5)
      m_autoSavePending = true;
  }

//+------------------------------------------------------------------+
//| Probabilidad KNN (12D normalizado)                                 |
//+------------------------------------------------------------------+
double KnnClassifier::CalculateKNNProbability(double slope, double atr, double momentum, double volFlow,
      double adx, double rsi,
      double deltaVol, double spreadDev,
      double smcRatio, double relStrength,
      double normVolatility, double volRatio,
      int kNeighbors) const
  {
   if(m_total == 0)
      return 0.0;
   int k = MathMin(kNeighbors, m_total);
   if(k > 200)
      k = 200;
   datetime now = TimeCurrent();

   DistDir heap[];
   ArrayResize(heap, k);
   int heapSize = 0;

   double query[KNN_DIM] = { slope, atr, momentum, volFlow, adx, rsi,
                             deltaVol, spreadDev, smcRatio, relStrength,
                             normVolatility, volRatio
                           };

   for(int i = 0; i < m_total; i++)
     {
      double distEuc = 0.0;
      double sampleVals[KNN_DIM] =
        {
         m_samples[i].slope, m_samples[i].atr, m_samples[i].momentum, m_samples[i].volFlow,
         m_samples[i].adx, m_samples[i].rsi, m_samples[i].deltaVol, m_samples[i].spreadDev,
         m_samples[i].smcRatio, m_samples[i].relStrength, m_samples[i].normVolatility, m_samples[i].volRatio
        };
      for(int d = 0; d < KNN_DIM; d++)
        {
         double diff = query[d] - sampleVals[d];
         diff = NormalizeDifference(diff, d);
         distEuc += diff * diff;
        }
      distEuc = MathSqrt(distEuc);

      // Decaimiento temporal
      double hours = (double)(now - m_samples[i].time) / 3600.0;
      double factor = MathExp(m_lambda * hours);
      distEuc *= factor;

      // Max‑heap de tamaño k
      if(heapSize < k)
        {
         heap[heapSize].dist = distEuc;
         heap[heapSize].dir  = m_samples[i].direction;
         int idx = heapSize;
         while(idx > 0)
           {
            int parent = (idx - 1) / 2;
            if(heap[parent].dist < heap[idx].dist)
              {
               DistDir temp = heap[parent];
               heap[parent] = heap[idx];
               heap[idx] = temp;
               idx = parent;
              }
            else
               break;
           }
         heapSize++;
        }
      else
         if(distEuc < heap[0].dist)
           {
            heap[0].dist = distEuc;
            heap[0].dir = m_samples[i].direction;
            int idx = 0;
            while(true)
              {
               int largest = idx, left = 2*idx+1, right = 2*idx+2;
               if(left  < heapSize && heap[left].dist  > heap[largest].dist)
                  largest = left;
               if(right < heapSize && heap[right].dist > heap[largest].dist)
                  largest = right;
               if(largest != idx)
                 {
                  DistDir temp = heap[idx];
                  heap[idx] = heap[largest];
                  heap[largest] = temp;
                  idx = largest;
                 }
               else
                  break;
              }
           }
     }

   int bullishVotes = 0, bearishVotes = 0;
   for(int i = 0; i < heapSize; i++)
     {
      if(heap[i].dir == 1)
         bullishVotes++;
      else
         if(heap[i].dir == -1)
            bearishVotes++;
     }
   return (double)(bullishVotes - bearishVotes) / k;
  }

//+------------------------------------------------------------------+
//| Guardar / Cargar estado (12 dimensiones)                          |
//+------------------------------------------------------------------+
bool KnnClassifier::SaveState(string fileName)
  {
   int handle = FileOpen(fileName, FILE_BIN | FILE_WRITE);
   if(handle == INVALID_HANDLE)
     {
      Print("Error saving ", fileName, ": ", GetLastError());
      return false;
     }
   FileWriteInteger(handle, m_total);
   FileWriteInteger(handle, m_insertIndex);
   FileWriteDouble(handle, m_lambda);
   uint written = FileWriteArray(handle, m_samples, 0, m_total);
   FileWriteInteger(handle, m_countStats);
   FileWriteArray(handle, m_mean, 0, KNN_DIM);
   FileWriteArray(handle, m_m2, 0, KNN_DIM);
   FileClose(handle);
   if(written != (uint)m_total)
     {
      Print("Warning: not all samples were written to ", fileName);
      return false;
     }
// ... después de escribir correctamente ...
   m_autoSavePending = false;
   m_samplesSinceSave = 0;
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool KnnClassifier::LoadState(string fileName)
  {
   int handle = FileOpen(fileName, FILE_BIN | FILE_READ);
   if(handle == INVALID_HANDLE)
      return false;
   m_total = FileReadInteger(handle);
   m_insertIndex = FileReadInteger(handle);
   m_lambda = FileReadDouble(handle);
   if(m_total < 0 || m_total > m_capacity)
     {
      FileClose(handle);
      return false;
     }
   ArrayResize(m_samples, m_capacity);
   uint read = FileReadArray(handle, m_samples, 0, m_total);
   m_countStats = FileReadInteger(handle);
   FileReadArray(handle, m_mean, 0, KNN_DIM);
   FileReadArray(handle, m_m2, 0, KNN_DIM);
   FileClose(handle);
   if(read != (uint)m_total)
     {
      Print("Error reading samples");
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Exportar a CSV (12 features + direction + time)                   |
//+------------------------------------------------------------------+
bool KnnClassifier::ExportSamplesToCSV(string fileName)
  {
   if(m_total == 0)
     {
      Print("KNN: no samples to export.");
      return false;
     }

   int handle = FileOpen(fileName, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
     {
      Print("Error creating ", fileName, ": ", GetLastError());
      return false;
     }

   FileWrite(handle, "slope,atr,momentum,volFlow,adx,rsi,deltaVol,spreadDev,smcRatio,relStrength,normVolatility,volRatio,direction,time");

   int exported = 0;
   for(int i = 0; i < m_total; i++)
     {
      if(m_samples[i].direction == 0)
         continue;
      if(MathAbs(m_samples[i].momentum) < 1e-6)
         continue;
      if(MathAbs(m_samples[i].volFlow) > 10.0 * m_samples[i].atr)
         continue;

      string line = StringFormat("%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%d,%d",
                                 m_samples[i].slope, m_samples[i].atr, m_samples[i].momentum,
                                 m_samples[i].volFlow, m_samples[i].adx, m_samples[i].rsi,
                                 m_samples[i].deltaVol, m_samples[i].spreadDev, m_samples[i].smcRatio,
                                 m_samples[i].relStrength, m_samples[i].normVolatility, m_samples[i].volRatio,
                                 m_samples[i].direction, (long)m_samples[i].time);
      FileWrite(handle, line);
      exported++;
     }

   double var[KNN_DIM];
   for(int d = 0; d < KNN_DIM; d++)
      var[d] = (m_countStats > 1) ? m_m2[d] / (m_countStats - 1) : 0.0;

   string statsLine = "#stats";
   for(int d = 0; d < KNN_DIM; d++)
      statsLine += StringFormat(",%.10f", m_mean[d]);
   for(int d = 0; d < KNN_DIM; d++)
      statsLine += StringFormat(",%.10f", var[d]);
   statsLine += StringFormat(",%d", m_countStats);
   FileWrite(handle, statsLine);

   FileClose(handle);
   Print("KNN: exported ", exported, " quality samples to ", fileName);
   return true;
  }

#endif // __KNNCLASSIFIER_MQH__
//+------------------------------------------------------------------+
