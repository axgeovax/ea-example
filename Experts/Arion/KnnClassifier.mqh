//+------------------------------------------------------------------+
//|                                               KnnClassifier.mqh  |
//|                        Arion - KNN 12D robusto v2.0               |
//|          Preparado para recibir etiquetas de retorno futuro      |
//|                        Autor: Alexy Hernandez                    |
//|                        Version: 2.0                              |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernandez. Todos los derechos reservados."
#property link      "https://github.com/axgeovax"
#property version   "2.0"
#property strict

#ifndef __KNNCLASSIFIER_MQH__
#define __KNNCLASSIFIER_MQH__

#include "SmartMoney.mqh"   // Para acceder a TrainingLabelGenerator

#define KNN_DIM 12
#define SCALE_BUFFER_SIZE 500
#define AUTO_PRUNE_HOURS 720
#define AUTO_PRUNE_MIN_SAMPLES 200

struct KDNode
  {
   double            point[KNN_DIM];
   double            direction;
   datetime          time;
   int               left;
   int               right;
   int               splitDim;
  };

struct KnnSample
  {
   double            slope, atr, momentum, volFlow, adx, rsi;
   double            deltaVol, spreadDev, smcRatio, relStrength;
   double            normVolatility, volRatio;
   double            direction;
   datetime          time;
  };

struct DistDir { double dist; double dir; };

//+------------------------------------------------------------------+
//| Clase KnnClassifier                                               |
//+------------------------------------------------------------------+
class KnnClassifier
  {
private:
   KnnSample         m_samples[];
   int               m_capacity, m_total, m_insertIndex;
   double            m_lambda;

   double            m_median[KNN_DIM];
   double            m_scale[KNN_DIM];
   int               m_countStats;

   double            m_scaleBuffer[KNN_DIM][SCALE_BUFFER_SIZE];
   int               m_scaleBufferIdx[KNN_DIM];
   int               m_scaleBufferCount[KNN_DIM];

   int               m_samplesSinceSave;
   bool              m_autoSavePending;

   KDNode            m_kdNodes[];
   bool              m_kdTreeBuilt;
   int               m_kdRoot;

   bool              m_ageWeightingEnabled;
   double            m_maxAgeHours;

   void              UpdateRealStatistics(const KnnSample &sample);
   double            NormalizeFeature(double value, int dimension) const;
   void              RecalculateMedianAndIQR(int dimension);
   void              PushToScaleBuffer(int dimension, double value);

   void              BuildKDTree();
   int               BuildKDTreeRecursive(int &indices[], int start, int count, int depth);
   void              NearestNeighborsKD(int node, const double &query[], DistDir &heap[], int &heapSize, int k, datetime now) const;

   double            CalculateKNNProbabilityLinear(const double &query[], int k, datetime now) const;

public:
                     KnnClassifier(int capacity = 500, double lambda = 0.002);
                    ~KnnClassifier() {}

   void              AddSample(double slope, double atr, double momentum, double volFlow,
                               double adx, double rsi, double direction,
                               double deltaVol = 0.0, double spreadDev = 0.0,
                               double smcRatio = 0.0, double relStrength = 0.0,
                               double normVolatility = 0.0, double volRatio = 1.0);

   // NUEVO: Añade una muestra usando el generador de etiquetas reales
   bool              AddSampleFromLabelGenerator(TrainingLabelGenerator &labelGen);

   double            CalculateKNNProbability(double slope, double atr, double momentum, double volFlow,
         double adx, double rsi,
         double deltaVol = 0.0, double spreadDev = 0.0,
         double smcRatio = 0.0, double relStrength = 0.0,
         double normVolatility = 0.0, double volRatio = 1.0,
         int kNeighbors = 15);

   bool              SaveState(string fileName);
   bool              LoadState(string fileName);
   bool              ExportSamplesToCSV(string fileName);

   bool              IsAutoSavePending() const { return m_autoSavePending; }
   void              ResetAutoSaveFlag() { m_autoSavePending = false; m_samplesSinceSave = 0; }

   void              SetLambda(double lambda) { m_lambda = MathMax(0.0, MathMin(0.01, lambda)); }
   double            GetLambda() const { return m_lambda; }

   void              SetMaxSamples(int maxSamples);
   void              PruneOldSamples(double maxAgeHours);
   double            GetDataFreshnessScore();
   int               GetTotalSamples() const { return m_total; }
   int               GetCapacity() const { return m_capacity; }

   void              SetAgeWeighting(bool enable, double maxAgeHours = 168.0);
   bool              GetAgeWeighting() const { return m_ageWeightingEnabled; }
   double            GetMaxAgeHours() const { return m_maxAgeHours; }
  };

//+------------------------------------------------------------------+
//| Constructor                                                        |
//+------------------------------------------------------------------+
KnnClassifier::KnnClassifier(int capacity, double lambda)
  {
   m_capacity = MathMin(MathMax(1, capacity), 10000);
   ArrayResize(m_samples, m_capacity);
   m_total = 0;
   m_insertIndex = 0;
   m_lambda = MathMax(0.0, MathMin(0.01, lambda));

   ArrayInitialize(m_median, 0.0);
   ArrayInitialize(m_scale, 1.0);
   m_countStats = 0;

   for(int d = 0; d < KNN_DIM; d++)
     {
      for(int j = 0; j < SCALE_BUFFER_SIZE; j++)
         m_scaleBuffer[d][j] = 0.0;
      m_scaleBufferIdx[d] = 0;
      m_scaleBufferCount[d] = 0;
     }

   m_samplesSinceSave = 0;
   m_autoSavePending = false;
   m_kdTreeBuilt = false;
   m_kdRoot = -1;
   ArrayResize(m_kdNodes, 0);

   m_ageWeightingEnabled = false;
   m_maxAgeHours = 168.0;
  }

//+------------------------------------------------------------------+
//| Agrega valor al buffer circular                                   |
//+------------------------------------------------------------------+
void KnnClassifier::PushToScaleBuffer(int dimension, double value)
  {
   int idx = m_scaleBufferIdx[dimension];
   m_scaleBuffer[dimension][idx] = value;
   m_scaleBufferIdx[dimension] = (idx + 1) % SCALE_BUFFER_SIZE;
   if(m_scaleBufferCount[dimension] < SCALE_BUFFER_SIZE)
      m_scaleBufferCount[dimension]++;
  }

//+------------------------------------------------------------------+
//| Recalcula la mediana y el IQR de una dimension                    |
//+------------------------------------------------------------------+
void KnnClassifier::RecalculateMedianAndIQR(int dimension)
  {
   int count = m_scaleBufferCount[dimension];
   if(count == 0)
      return;

   double sorted[];
   ArrayResize(sorted, count);
   for(int i = 0; i < count; i++)
      sorted[i] = m_scaleBuffer[dimension][i];

   ArraySort(sorted);

   double median;
   if(count % 2 == 1)
      median = sorted[count / 2];
   else
      median = (sorted[count / 2 - 1] + sorted[count / 2]) / 2.0;

   m_median[dimension] = median;

   double q1, q3;
   if(count >= 4)
     {
      int iq1 = (int)MathRound(count * 0.25);
      int iq3 = (int)MathRound(count * 0.75);
      if(iq1 < 0)
         iq1 = 0;
      if(iq3 >= count)
         iq3 = count - 1;
      q1 = sorted[iq1];
      q3 = sorted[iq3];
     }
   else
     {
      q1 = sorted[0];
      q3 = sorted[count-1];
     }

   double iqr = q3 - q1;
   if(iqr <= 1e-12)
      iqr = 1e-8;

   m_scale[dimension] = 0.5 * iqr;
  }

//+------------------------------------------------------------------+
//| Actualiza estadisticas reales con cada nueva muestra.             |
//+------------------------------------------------------------------+
void KnnClassifier::UpdateRealStatistics(const KnnSample &sample)
  {
   double val[KNN_DIM] =
     {
      sample.slope, sample.atr, sample.momentum, sample.volFlow,
      sample.adx, sample.rsi, sample.deltaVol, sample.spreadDev,
      sample.smcRatio, sample.relStrength, sample.normVolatility, sample.volRatio
     };

   for(int d = 0; d < KNN_DIM; d++)
      PushToScaleBuffer(d, val[d]);

   if(m_countStats == 0)
     {
      for(int d = 0; d < KNN_DIM; d++)
        {
         m_median[d] = val[d];
         m_scale[d]  = 1.0;
        }
      m_countStats = 1;
      return;
     }

   m_countStats++;

   if(m_countStats % 10 == 0 || m_scaleBufferCount[0] >= SCALE_BUFFER_SIZE)
     {
      for(int d = 0; d < KNN_DIM; d++)
         RecalculateMedianAndIQR(d);
     }

   if(m_total > AUTO_PRUNE_MIN_SAMPLES)
     {
      static int pruneCounter = 0;
      pruneCounter++;
      if(pruneCounter >= 100)
        {
         PruneOldSamples(AUTO_PRUNE_HOURS);
         pruneCounter = 0;
        }
     }
  }

//+------------------------------------------------------------------+
//| Normaliza una caracteristica                                      |
//+------------------------------------------------------------------+
double KnnClassifier::NormalizeFeature(double value, int dimension) const
  {
   if(dimension < 0 || dimension >= KNN_DIM)
      return 0.0;

   double scale = m_scale[dimension];
   if(scale <= 1e-12)
      scale = 1e-12;

   return (value - m_median[dimension]) / scale;
  }

//+------------------------------------------------------------------+
//| Anade una nueva muestra                                           |
//+------------------------------------------------------------------+
void KnnClassifier::AddSample(double slope, double atr, double momentum, double volFlow,
                              double adx, double rsi, double direction,
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
   UpdateRealStatistics(sample);
   m_kdTreeBuilt = false;
   m_samplesSinceSave++;
   if(m_samplesSinceSave >= 5)
      m_autoSavePending = true;
  }

//+------------------------------------------------------------------+
//| Construye el KD-Tree                                              |
//+------------------------------------------------------------------+
void KnnClassifier::BuildKDTree()
  {
   if(m_total == 0)
      return;
   ArrayResize(m_kdNodes, m_total);
   int indices[];
   ArrayResize(indices, m_total);
   for(int i = 0; i < m_total; i++)
      indices[i] = i;
   m_kdRoot = BuildKDTreeRecursive(indices, 0, m_total, 0);
   m_kdTreeBuilt = true;
  }

//+------------------------------------------------------------------+
//| Construccion recursiva del KD-Tree                                |
//+------------------------------------------------------------------+
int KnnClassifier::BuildKDTreeRecursive(int &indices[], int start, int count, int depth)
  {
   if(count == 0)
      return -1;
   int dim = depth % KNN_DIM;

// Ordenacion parcial para encontrar la mediana
   for(int i = start; i < start + count - 1; i++)
      for(int j = i + 1; j < start + count; j++)
        {
         double valI = (dim == 0) ? m_samples[indices[i]].slope :
                       (dim == 1) ? m_samples[indices[i]].atr :
                       (dim == 2) ? m_samples[indices[i]].momentum :
                       (dim == 3) ? m_samples[indices[i]].volFlow :
                       (dim == 4) ? m_samples[indices[i]].adx :
                       (dim == 5) ? m_samples[indices[i]].rsi :
                       (dim == 6) ? m_samples[indices[i]].deltaVol :
                       (dim == 7) ? m_samples[indices[i]].spreadDev :
                       (dim == 8) ? m_samples[indices[i]].smcRatio :
                       (dim == 9) ? m_samples[indices[i]].relStrength :
                       (dim == 10) ? m_samples[indices[i]].normVolatility :
                       m_samples[indices[i]].volRatio;
         double valJ = (dim == 0) ? m_samples[indices[j]].slope :
                       (dim == 1) ? m_samples[indices[j]].atr :
                       (dim == 2) ? m_samples[indices[j]].momentum :
                       (dim == 3) ? m_samples[indices[j]].volFlow :
                       (dim == 4) ? m_samples[indices[j]].adx :
                       (dim == 5) ? m_samples[indices[j]].rsi :
                       (dim == 6) ? m_samples[indices[j]].deltaVol :
                       (dim == 7) ? m_samples[indices[j]].spreadDev :
                       (dim == 8) ? m_samples[indices[j]].smcRatio :
                       (dim == 9) ? m_samples[indices[j]].relStrength :
                       (dim == 10) ? m_samples[indices[j]].normVolatility :
                       m_samples[indices[j]].volRatio;
         if(valI > valJ)
           {
            int tmp = indices[i];
            indices[i] = indices[j];
            indices[j] = tmp;
           }
        }

   int median = start + count / 2;
   int nodeIdx = indices[median];

   m_kdNodes[nodeIdx].point[0]  = m_samples[nodeIdx].slope;
   m_kdNodes[nodeIdx].point[1]  = m_samples[nodeIdx].atr;
   m_kdNodes[nodeIdx].point[2]  = m_samples[nodeIdx].momentum;
   m_kdNodes[nodeIdx].point[3]  = m_samples[nodeIdx].volFlow;
   m_kdNodes[nodeIdx].point[4]  = m_samples[nodeIdx].adx;
   m_kdNodes[nodeIdx].point[5]  = m_samples[nodeIdx].rsi;
   m_kdNodes[nodeIdx].point[6]  = m_samples[nodeIdx].deltaVol;
   m_kdNodes[nodeIdx].point[7]  = m_samples[nodeIdx].spreadDev;
   m_kdNodes[nodeIdx].point[8]  = m_samples[nodeIdx].smcRatio;
   m_kdNodes[nodeIdx].point[9]  = m_samples[nodeIdx].relStrength;
   m_kdNodes[nodeIdx].point[10] = m_samples[nodeIdx].normVolatility;
   m_kdNodes[nodeIdx].point[11] = m_samples[nodeIdx].volRatio;
   m_kdNodes[nodeIdx].direction = m_samples[nodeIdx].direction;
   m_kdNodes[nodeIdx].time      = m_samples[nodeIdx].time;
   m_kdNodes[nodeIdx].splitDim  = dim;

   int leftCount  = median - start;
   m_kdNodes[nodeIdx].left  = BuildKDTreeRecursive(indices, start, leftCount, depth + 1);
   int rightStart = median + 1;
   int rightCount = count - (median - start) - 1;
   m_kdNodes[nodeIdx].right = BuildKDTreeRecursive(indices, rightStart, rightCount, depth + 1);

   return nodeIdx;
  }

//+------------------------------------------------------------------+
//| Busqueda en KD-Tree                                               |
//+------------------------------------------------------------------+
void KnnClassifier::NearestNeighborsKD(int node, const double &query[], DistDir &heap[], int &heapSize, int k, datetime now) const
  {
   if(node == -1)
      return;

   double distEuc = 0.0;
   for(int d = 0; d < KNN_DIM; d++)
     {
      double diff = NormalizeFeature(query[d], d) - NormalizeFeature(m_kdNodes[node].point[d], d);
      distEuc += diff * diff;
     }
   distEuc = MathSqrt(distEuc);

   double hours = (double)(now - m_kdNodes[node].time) / 3600.0;

   if(m_ageWeightingEnabled && hours > m_maxAgeHours)
      return;

   distEuc *= MathExp(m_lambda * hours);

   if(heapSize < k)
     {
      heap[heapSize].dist = distEuc;
      heap[heapSize].dir  = m_kdNodes[node].direction;
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
         heap[0].dir  = m_kdNodes[node].direction;
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

   int dim = m_kdNodes[node].splitDim;
   double diff = NormalizeFeature(query[dim], dim) - NormalizeFeature(m_kdNodes[node].point[dim], dim);
   double distToSplit = diff * diff;

   if(diff < 0)
     {
      NearestNeighborsKD(m_kdNodes[node].left, query, heap, heapSize, k, now);
      if(heapSize < k || distToSplit < heap[0].dist * heap[0].dist)
         NearestNeighborsKD(m_kdNodes[node].right, query, heap, heapSize, k, now);
     }
   else
     {
      NearestNeighborsKD(m_kdNodes[node].right, query, heap, heapSize, k, now);
      if(heapSize < k || distToSplit < heap[0].dist * heap[0].dist)
         NearestNeighborsKD(m_kdNodes[node].left, query, heap, heapSize, k, now);
     }
  }

//+------------------------------------------------------------------+
//| Busqueda lineal                                                   |
//+------------------------------------------------------------------+
double KnnClassifier::CalculateKNNProbabilityLinear(const double &query[], int k, datetime now) const
  {
   DistDir heap[];
   ArrayResize(heap, k);
   int heapSize = 0;

   for(int i = 0; i < m_total; i++)
     {
      double hours = (double)(now - m_samples[i].time) / 3600.0;

      if(m_ageWeightingEnabled && hours > m_maxAgeHours)
         continue;

      double distEuc = 0.0;
      double sampleVals[KNN_DIM] =
        {
         m_samples[i].slope, m_samples[i].atr, m_samples[i].momentum, m_samples[i].volFlow,
         m_samples[i].adx, m_samples[i].rsi, m_samples[i].deltaVol, m_samples[i].spreadDev,
         m_samples[i].smcRatio, m_samples[i].relStrength, m_samples[i].normVolatility, m_samples[i].volRatio
        };
      for(int d = 0; d < KNN_DIM; d++)
        {
         double diff = NormalizeFeature(query[d], d) - NormalizeFeature(sampleVals[d], d);
         distEuc += diff * diff;
        }
      distEuc = MathSqrt(distEuc);
      distEuc *= MathExp(m_lambda * hours);

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

   double bullishVotes = 0.0, bearishVotes = 0.0;
   for(int i = 0; i < heapSize; i++)
     {
      if(heap[i].dir > 0.0)
         bullishVotes += MathAbs(heap[i].dir);
      else
         if(heap[i].dir < 0.0)
            bearishVotes += MathAbs(heap[i].dir);
     }

   double totalVotes = bullishVotes + bearishVotes;
   if(totalVotes == 0.0)
      return 0.0;
   return (bullishVotes - bearishVotes) / totalVotes;
  }

//+------------------------------------------------------------------+
//| Calcula probabilidad KNN                                          |
//+------------------------------------------------------------------+
double KnnClassifier::CalculateKNNProbability(double slope, double atr, double momentum, double volFlow,
      double adx, double rsi,
      double deltaVol, double spreadDev,
      double smcRatio, double relStrength,
      double normVolatility, double volRatio,
      int kNeighbors)
  {
   if(m_total == 0)
      return 0.0;
   int k = MathMin(kNeighbors, m_total);
   if(k > 200)
      k = 200;
   datetime now = TimeCurrent();

   double query[KNN_DIM] = { slope, atr, momentum, volFlow, adx, rsi,
                             deltaVol, spreadDev, smcRatio, relStrength,
                             normVolatility, volRatio
                           };

   if(m_total > 1000)
     {
      if(!m_kdTreeBuilt)
         BuildKDTree();
      DistDir heap[];
      ArrayResize(heap, k);
      int heapSize = 0;
      NearestNeighborsKD(m_kdRoot, query, heap, heapSize, k, now);

      double bullishVotes = 0.0, bearishVotes = 0.0;
      for(int i = 0; i < heapSize; i++)
        {
         if(heap[i].dir > 0.0)
            bullishVotes += MathAbs(heap[i].dir);
         else
            if(heap[i].dir < 0.0)
               bearishVotes += MathAbs(heap[i].dir);
        }
      double totalVotes = bullishVotes + bearishVotes;
      return (totalVotes > 0.0) ? (bullishVotes - bearishVotes) / totalVotes : 0.0;
     }
   else
      return CalculateKNNProbabilityLinear(query, k, now);
  }

//+------------------------------------------------------------------+
//| AddSampleFromLabelGenerator                                       |
//+------------------------------------------------------------------+
bool KnnClassifier::AddSampleFromLabelGenerator(TrainingLabelGenerator &labelGen)
  {
   if(!labelGen.IsReady())
      return false;

   double features[];
   if(!labelGen.GetFeatures(features))
      return false;

   double realDirection = labelGen.GetLabel();

   AddSample(features[0], features[1], features[2], features[3],
             features[4], features[5], realDirection,
             features[6], features[7], features[8], features[9],
             features[10], features[11]);
   return true;
  }

//+------------------------------------------------------------------+
//| Persistencia                                                      |
//+------------------------------------------------------------------+
bool KnnClassifier::SaveState(string fileName)
  {
   int handle = FileOpen(fileName, FILE_BIN | FILE_WRITE);
   if(handle == INVALID_HANDLE)
      return false;
   FileWriteInteger(handle, m_total);
   FileWriteInteger(handle, m_insertIndex);
   FileWriteDouble(handle, m_lambda);
   FileWriteInteger(handle, m_capacity);
   FileWriteInteger(handle, m_countStats);
   FileWriteArray(handle, m_median, 0, KNN_DIM);
   FileWriteArray(handle, m_scale, 0, KNN_DIM);
   FileWriteInteger(handle, m_ageWeightingEnabled);
   FileWriteDouble(handle, m_maxAgeHours);
   uint written = FileWriteArray(handle, m_samples, 0, m_total);
   FileClose(handle);
   m_autoSavePending = false;
   m_samplesSinceSave = 0;
   return (written == (uint)m_total);
  }

//+------------------------------------------------------------------+
//| Carga estado                                                      |
//+------------------------------------------------------------------+
bool KnnClassifier::LoadState(string fileName)
  {
   if(!FileIsExist(fileName))
      return false;
   int handle = FileOpen(fileName, FILE_BIN | FILE_READ);
   if(handle == INVALID_HANDLE)
      return false;
   m_total = FileReadInteger(handle);
   m_insertIndex = FileReadInteger(handle);
   m_lambda = FileReadDouble(handle);
   m_capacity = FileReadInteger(handle);
   m_countStats = FileReadInteger(handle);
   FileReadArray(handle, m_median, 0, KNN_DIM);
   FileReadArray(handle, m_scale, 0, KNN_DIM);
   m_ageWeightingEnabled = (bool)FileReadInteger(handle);
   m_maxAgeHours = FileReadDouble(handle);
   ArrayResize(m_samples, m_capacity);
   uint read = FileReadArray(handle, m_samples, 0, m_total);
   FileClose(handle);
   m_kdTreeBuilt = false;

   for(int d = 0; d < KNN_DIM; d++)
     {
      for(int j = 0; j < SCALE_BUFFER_SIZE; j++)
         m_scaleBuffer[d][j] = 0.0;
      m_scaleBufferCount[d] = 0;
      m_scaleBufferIdx[d] = 0;
     }
   for(int i = 0; i < m_total; i++)
     {
      KnnSample s = m_samples[i];
      double val[KNN_DIM] = {s.slope, s.atr, s.momentum, s.volFlow, s.adx, s.rsi,
                             s.deltaVol, s.spreadDev, s.smcRatio, s.relStrength,
                             s.normVolatility, s.volRatio
                            };
      for(int d = 0; d < KNN_DIM; d++)
         PushToScaleBuffer(d, val[d]);
     }
   for(int d = 0; d < KNN_DIM; d++)
      RecalculateMedianAndIQR(d);

   return (read == (uint)m_total);
  }

//+------------------------------------------------------------------+
//| Exporta a CSV                                                     |
//+------------------------------------------------------------------+
bool KnnClassifier::ExportSamplesToCSV(string fileName)
  {
   if(m_total == 0)
      return false;
   int handle = FileOpen(fileName, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return false;
   FileWrite(handle, "slope,atr,momentum,volFlow,adx,rsi,deltaVol,spreadDev,smcRatio,relStrength,normVolatility,volRatio,direction,time");
   int exported = 0;
   for(int i = 0; i < m_total; i++)
     {
      string line = StringFormat("%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.1f,%d",
                                 m_samples[i].slope, m_samples[i].atr, m_samples[i].momentum,
                                 m_samples[i].volFlow, m_samples[i].adx, m_samples[i].rsi,
                                 m_samples[i].deltaVol, m_samples[i].spreadDev,
                                 m_samples[i].smcRatio, m_samples[i].relStrength,
                                 m_samples[i].normVolatility, m_samples[i].volRatio,
                                 m_samples[i].direction, (long)m_samples[i].time);
      FileWrite(handle, line);
      exported++;
     }
   FileClose(handle);
   Print("KNN: exported ", exported, " samples to ", fileName);
   return (exported > 0);
  }

//+------------------------------------------------------------------+
//| SetMaxSamples                                                     |
//+------------------------------------------------------------------+
void KnnClassifier::SetMaxSamples(int maxSamples)
  {
   int newCapacity = MathMin(MathMax(100, maxSamples), 10000);
   if(newCapacity == m_capacity)
      return;
   ArrayResize(m_samples, newCapacity);
   m_capacity = newCapacity;
   if(m_total > m_capacity)
      m_total = m_capacity;
   m_kdTreeBuilt = false;
   Print("KNN: capacity set to ", m_capacity, " samples");
  }

//+------------------------------------------------------------------+
//| Poda de muestras antiguas                                         |
//+------------------------------------------------------------------+
void KnnClassifier::PruneOldSamples(double maxAgeHours)
  {
   if(maxAgeHours <= 0 || m_total == 0)
      return;
   datetime cutoffTime = TimeCurrent() - (datetime)(maxAgeHours * 3600);
   int newTotal = 0;
   KnnSample tempSamples[];
   for(int i = 0; i < m_total; i++)
     {
      if(m_samples[i].time >= cutoffTime)
        {
         ArrayResize(tempSamples, newTotal + 1);
         tempSamples[newTotal] = m_samples[i];
         newTotal++;
        }
     }
   if(newTotal < m_total)
     {
      ArrayCopy(m_samples, tempSamples, 0, 0, newTotal);
      m_total = newTotal;
      m_insertIndex = newTotal;
      m_kdTreeBuilt = false;
      m_countStats = 0;
      ArrayInitialize(m_median, 0.0);
      ArrayInitialize(m_scale, 1.0);
      for(int d=0; d<KNN_DIM; d++)
        {
         for(int j=0; j<SCALE_BUFFER_SIZE; j++)
            m_scaleBuffer[d][j] = 0.0;
         m_scaleBufferCount[d] = 0;
         m_scaleBufferIdx[d] = 0;
        }
      for(int i = 0; i < m_total; i++)
         UpdateRealStatistics(m_samples[i]);
      Print("KNN: pruned ", (m_total - newTotal), " old samples. Remaining: ", m_total);
     }
  }

//+------------------------------------------------------------------+
//| Puntuacion de frescura de datos                                   |
//+------------------------------------------------------------------+
double KnnClassifier::GetDataFreshnessScore()
  {
   if(m_total == 0)
      return 0.0;
   datetime now = TimeCurrent();
   double totalAge = 0.0;
   for(int i = 0; i < m_total; i++)
      totalAge += (double)(now - m_samples[i].time) / 3600.0;
   double avgAgeHours = totalAge / m_total;
   double freshnessScore = 0.0;
   if(avgAgeHours < 24.0)
      freshnessScore = 1.0;
   else
      if(avgAgeHours < 168.0)
         freshnessScore = 1.0 - (avgAgeHours - 24.0) / 144.0;
      else
         if(avgAgeHours < 720.0)
            freshnessScore = 0.5 - (avgAgeHours - 168.0) / 1104.0;
         else
            freshnessScore = 0.0;
   return MathMax(0.0, freshnessScore);
  }

//+------------------------------------------------------------------+
//| Configura ponderacion por edad                                    |
//+------------------------------------------------------------------+
void KnnClassifier::SetAgeWeighting(bool enable, double maxAgeHours)
  {
   m_ageWeightingEnabled = enable;
   if(enable)
      m_maxAgeHours = (maxAgeHours > 0) ? maxAgeHours : 168.0;
   Print("KNN: age weighting ", enable ? "enabled" : "disabled");
  }

#endif // __KNNCLASSIFIER_MQH__
