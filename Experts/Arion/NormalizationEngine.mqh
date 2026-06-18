//+------------------------------------------------------------------+
//|                                          NormalizationEngine.mqh |
//|                        Arion - Motor de Normalizacion Centralizado|
//|          * DINAMICO: Umbrales de validacion auto-calibrados      |
//|                        Autor: Alexy Hernandez                    |
//|                        Version: 1.0                              |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernandez. Todos los derechos reservados."
#property link      "https://github.com/axgeovax"
#property version   "1.0"
#property strict

#ifndef __NORMALIZATIONENGINE_MQH__
#define __NORMALIZATIONENGINE_MQH__

#define NORM_FEATURES 12

struct NormalizationStats
  {
   double            mean[NORM_FEATURES];
   double            std[NORM_FEATURES];
   double            min[NORM_FEATURES];
   double            max[NORM_FEATURES];
   int               sampleCount;
   datetime          lastUpdate;
  };

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class NormalizationEngine
  {
private:
   string            m_symbol;
   NormalizationStats m_stats;
   bool              m_paramsLoaded;

   double            m_minValidThreshold[NORM_FEATURES];
   double            m_maxValidThreshold[NORM_FEATURES];
   bool              m_thresholdsCalibrated;

   double            m_featureSum[NORM_FEATURES];
   double            m_featureSumSq[NORM_FEATURES];
   int               m_featureCount[NORM_FEATURES];
   int               m_totalSamples;

   void              AutoCalibrateThresholds();
   bool              ValidateFeatureIndex(int index);
   double            CalculatePenalty(double value, int index);

public:
                     NormalizationEngine(string symbol = NULL);
                    ~NormalizationEngine();

   bool              LoadParams(string normPath = "Arion\\ArionIntelligence.norm");
   bool              SaveParams(string normPath = "Arion\\ArionIntelligence.norm");

   void              NormalizeFeature(double &features[], int startIndex = 0);
   void              NormalizeSingleFeature(double &value, int index);

   double            GetValidatedScore(double &features[]);
   bool              ValidateFeatureRange(double &features[], double &validityScores[]);
   bool              IsFeatureValid(double value, int index);

   void              UpdateStatsStreaming(const double &newSample[]);
   void              ResetStreamingStats();

   NormalizationStats GetStats() const { return m_stats; }
   bool              IsParamsLoaded() const { return m_paramsLoaded; }
   int               GetFeatureCount() const { return NORM_FEATURES; }

   void              SetCustomThresholds(double &minThresholds[], double &maxThresholds[]);
   void              GetThresholds(double &minThresholds[], double &maxThresholds[]);
  };

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
NormalizationEngine::NormalizationEngine(string symbol)
  {
   m_symbol = (symbol == NULL) ? _Symbol : symbol;
   m_paramsLoaded = false;
   m_thresholdsCalibrated = false;
   ArrayInitialize(m_stats.mean, 0.0);
   ArrayInitialize(m_stats.std, 1.0);
   ArrayInitialize(m_stats.min, 0.0);
   ArrayInitialize(m_stats.max, 0.0);
   m_stats.sampleCount = 0;
   m_stats.lastUpdate = 0;
   for(int i = 0; i < NORM_FEATURES; i++)
     {
      m_minValidThreshold[i] = -1e12;
      m_maxValidThreshold[i] = 1e12;
     }
   ArrayInitialize(m_featureSum, 0.0);
   ArrayInitialize(m_featureSumSq, 0.0);
   ArrayInitialize(m_featureCount, 0);
   m_totalSamples = 0;
  }

NormalizationEngine::~NormalizationEngine() {}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void NormalizationEngine::AutoCalibrateThresholds()
  {
   if(m_totalSamples < 100)
      return;
   for(int i = 0; i < NORM_FEATURES; i++)
     {
      if(m_featureCount[i] < 50)
         continue;
      double mean = m_featureSum[i] / m_featureCount[i];
      double variance = (m_featureSumSq[i] / m_featureCount[i]) - (mean*mean);
      if(variance < 0)
         variance = 0;
      double std = MathSqrt(variance);
      if(std == 0)
         std = MathAbs(mean)*0.01 + 1e-8;
      m_minValidThreshold[i] = mean - 5.0*std;
      m_maxValidThreshold[i] = mean + 5.0*std;
     }
   m_thresholdsCalibrated = true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool NormalizationEngine::LoadParams(string normPath)
  {
   if(!FileIsExist(normPath))
     {
      m_paramsLoaded = false;
      return false;
     }
   int handle = FileOpen(normPath, FILE_BIN | FILE_READ);
   if(handle == INVALID_HANDLE)
      return false;
   double means[NORM_FEATURES], stds[NORM_FEATURES];
   if(FileReadArray(handle, means, 0, NORM_FEATURES) != NORM_FEATURES ||
      FileReadArray(handle, stds, 0, NORM_FEATURES) != NORM_FEATURES)
     { FileClose(handle); return false; }
   FileClose(handle);
   for(int i = 0; i < NORM_FEATURES; i++)
     {
      m_stats.mean[i] = means[i];
      m_stats.std[i] = (stds[i] > 0.0) ? stds[i] : 1.0;
     }
   m_paramsLoaded = true;
   m_stats.lastUpdate = TimeCurrent();
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool NormalizationEngine::SaveParams(string normPath)
  {
   int handle = FileOpen(normPath, FILE_BIN | FILE_WRITE);
   if(handle == INVALID_HANDLE)
      return false;
   FileWriteArray(handle, m_stats.mean, 0, NORM_FEATURES);
   FileWriteArray(handle, m_stats.std, 0, NORM_FEATURES);
   FileClose(handle);
   m_stats.lastUpdate = TimeCurrent();
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void NormalizationEngine::NormalizeFeature(double &features[], int startIndex)
  {
   int totalFeatures = ArraySize(features);
   if(totalFeatures == 0)
      return;
   for(int i = 0; i < totalFeatures; i++)
     { int normIndex = startIndex + i; if(normIndex >= NORM_FEATURES) break; NormalizeSingleFeature(features[i], normIndex); }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void NormalizationEngine::NormalizeSingleFeature(double &value, int index)
  {
   if(!ValidateFeatureIndex(index) || !m_paramsLoaded)
      return;
   double std = (m_stats.std[index] > 1e-12) ? m_stats.std[index] : 1.0;
   value = (value - m_stats.mean[index]) / std;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double NormalizationEngine::GetValidatedScore(double &features[])
  {
   int featureCount = MathMin(ArraySize(features), NORM_FEATURES);
   if(featureCount == 0)
      return 0.0;
   double totalScore = 0.0;
   int validFeatures = 0;
   for(int i = 0; i < featureCount; i++)
     {
      if(IsFeatureValid(features[i], i))
        {
         totalScore += 1.0;
         validFeatures++;
        }
      else
        {
         double penalty = CalculatePenalty(features[i], i);
         totalScore += (1.0 - penalty);
         validFeatures++;
        }
     }
   return (validFeatures > 0) ? totalScore / validFeatures : 0.0;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool NormalizationEngine::ValidateFeatureRange(double &features[], double &validityScores[])
  {
   int featureCount = MathMin(ArraySize(features), NORM_FEATURES);
   if(featureCount == 0)
      return false;
   ArrayResize(validityScores, featureCount);
   bool allValid = true;
   for(int i = 0; i < featureCount; i++)
     {
      if(IsFeatureValid(features[i], i))
         validityScores[i] = 1.0;
      else
        {
         validityScores[i] = 1.0 - CalculatePenalty(features[i], i);
         allValid = false;
        }
     }
   return allValid;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool NormalizationEngine::IsFeatureValid(double value, int index)
  {
   if(!ValidateFeatureIndex(index) || !MathIsValidNumber(value))
      return false;
   if(!m_thresholdsCalibrated)
      return true;
   if(value < m_minValidThreshold[index] || value > m_maxValidThreshold[index])
      return false;
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double NormalizationEngine::CalculatePenalty(double value, int index)
  {
   if(!ValidateFeatureIndex(index) || !m_thresholdsCalibrated)
      return 0.0;
   double penalty = 0.0;
   if(value < m_minValidThreshold[index])
     { double range = m_maxValidThreshold[index] - m_minValidThreshold[index]; if(range > 0) penalty = (m_minValidThreshold[index] - value) / range; }
   else
      if(value > m_maxValidThreshold[index])
        { double range = m_maxValidThreshold[index] - m_minValidThreshold[index]; if(range > 0) penalty = (value - m_maxValidThreshold[index]) / range; }
   return MathMin(penalty, 1.0);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void NormalizationEngine::UpdateStatsStreaming(const double &newSample[])
  {
   int sampleSize = MathMin(ArraySize(newSample), NORM_FEATURES);
   if(sampleSize == 0)
      return;
   m_stats.sampleCount++;
   m_totalSamples++;
   for(int i = 0; i < sampleSize; i++)
     {
      double delta = newSample[i] - m_stats.mean[i];
      m_stats.mean[i] += delta / m_stats.sampleCount;
      double delta2 = newSample[i] - m_stats.mean[i];
      m_stats.std[i] += delta * delta2;
      if(m_stats.sampleCount == 1)
        {
         m_stats.min[i] = newSample[i];
         m_stats.max[i] = newSample[i];
        }
      else
        {
         m_stats.min[i] = MathMin(m_stats.min[i], newSample[i]);
         m_stats.max[i] = MathMax(m_stats.max[i], newSample[i]);
        }
      m_featureSum[i] += newSample[i];
      m_featureSumSq[i] += newSample[i] * newSample[i];
      m_featureCount[i]++;
     }
   for(int i = 0; i < sampleSize; i++)
      m_stats.std[i] = (m_stats.sampleCount > 1) ? MathSqrt(m_stats.std[i] / (m_stats.sampleCount - 1)) : 1.0;
   m_stats.lastUpdate = TimeCurrent();
   if(m_totalSamples % 100 == 0)
      AutoCalibrateThresholds();
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void NormalizationEngine::ResetStreamingStats()
  {
   ArrayInitialize(m_stats.mean, 0.0);
   ArrayInitialize(m_stats.std, 1.0);
   ArrayInitialize(m_stats.min, 0.0);
   ArrayInitialize(m_stats.max, 0.0);
   m_stats.sampleCount = 0;
   m_stats.lastUpdate = 0;
   ArrayInitialize(m_featureSum, 0.0);
   ArrayInitialize(m_featureSumSq, 0.0);
   ArrayInitialize(m_featureCount, 0);
   m_totalSamples = 0;
   m_thresholdsCalibrated = false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void NormalizationEngine::SetCustomThresholds(double &minThresholds[], double &maxThresholds[])
  {
   int count = MathMin(MathMin(ArraySize(minThresholds), ArraySize(maxThresholds)), NORM_FEATURES);
   if(count == 0)
      return;
   for(int i = 0; i < count; i++)
     {
      m_minValidThreshold[i] = minThresholds[i];
      m_maxValidThreshold[i] = maxThresholds[i];
     }
   m_thresholdsCalibrated = true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void NormalizationEngine::GetThresholds(double &minThresholds[], double &maxThresholds[])
  {
   ArrayResize(minThresholds, NORM_FEATURES);
   ArrayResize(maxThresholds, NORM_FEATURES);
   ArrayCopy(minThresholds, m_minValidThreshold);
   ArrayCopy(maxThresholds, m_maxValidThreshold);
  }

bool NormalizationEngine::ValidateFeatureIndex(int index) { return (index >= 0 && index < NORM_FEATURES); }

#endif // __NORMALIZATIONENGINE_MQH__
//+------------------------------------------------------------------+
