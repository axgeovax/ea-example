//+------------------------------------------------------------------+
//|                                                 ModelMonitor.mqh |
//|                        Arion - Monitor de Degradacion de Modelo   |
//|          * DINAMICO: Umbrales auto-calibrados con datos reales    |
//|                        Autor: Alexy Hernandez                    |
//|                        Version: 1.0                              |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernandez. Todos los derechos reservados."
#property link      "https://github.com/axgeovax"
#property version   "1.0"
#property strict

#ifndef __MODELMONITOR_MQH__
#define __MODELMONITOR_MQH__

#define MONITOR_HISTORY_SIZE 200
#define WARMUP_SAMPLES 100

struct PredictionRecord
  {
   datetime          timestamp;
   double            predictedDirection;
   double            onnxProbability;
   double            knnProbability;
   double            smcConfidence;
   double            actualDirection;
   bool              wasCorrect;
   double            predictionError;
  };

struct ModelStatistics
  {
   double            accuracy;
   double            precision;
   double            recall;
   double            f1Score;
   double            driftScore;
   int               totalPredictions;
   int               correctPredictions;
   double            avgPredictionError;
   double            predictionStdDev;
   datetime          lastUpdate;
   double            driftThreshold;
   double            performanceThreshold;
  };

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class ModelMonitor
  {
private:
   string            m_symbol;
   PredictionRecord  m_predictionHistory[];
   int               m_historyIndex;
   int               m_totalPredictions;
   ModelStatistics   m_stats;
   double            m_baselineAccuracy;
   double            m_baselineDriftScore;
   bool              m_baselinesEstablished;
   double            m_featureBaseline[12];
   double            m_featureCurrent[12];
   int               m_featureSampleCount;
   double            m_driftHistory[];
   int               m_driftHistoryCount;
   double            m_driftMean;
   double            m_driftStd;

   void              UpdateStatistics();
   double            CalculateDriftScore();
   void              DetectFeatureDrift(const double &features[]);
   void              AutoCalibrateThresholds();

public:
                     ModelMonitor(string symbol = NULL);
                    ~ModelMonitor();
   void              RecordPrediction(double predictedDirection,
                                      double onnxProbability,
                                      double knnProbability,
                                      double smcConfidence);
   void              RecordActualOutcome(double actualDirection);
   void              UpdateFeatureBaseline(const double &features[]);
   void              RecordCurrentFeatures(const double &features[]);
   bool              IsModelDegraded();
   bool              IsPerformanceDegraded();
   bool              IsDataDriftDetected();
   ModelStatistics   GetStatistics() const { return m_stats; }
   double            GetDriftScore() const { return m_stats.driftScore; }
   double            GetAccuracy() const { return m_stats.accuracy; }
   void              SetBaselineAccuracy(double accuracy);
   void              SetBaselineDriftScore(double driftScore);
   bool              SaveState(string fileName);
   bool              LoadState(string fileName);
   void              Reset();
   int               GetHistorySize() const { return m_totalPredictions; }
  };

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
ModelMonitor::ModelMonitor(string symbol)
  {
   m_symbol = (symbol == NULL) ? _Symbol : symbol;
   ArrayResize(m_predictionHistory, MONITOR_HISTORY_SIZE);
   for(int i = 0; i < MONITOR_HISTORY_SIZE; i++)
      ZeroMemory(m_predictionHistory[i]);
   m_historyIndex = 0;
   m_totalPredictions = 0;
   ZeroMemory(m_stats);
   m_stats.lastUpdate = 0;
   m_stats.driftThreshold = 0.3;
   m_stats.performanceThreshold = 0.55;
   m_baselineAccuracy = 0.0;
   m_baselineDriftScore = 0.0;
   m_baselinesEstablished = false;
   ArrayInitialize(m_featureBaseline, 0.0);
   ArrayInitialize(m_featureCurrent, 0.0);
   m_featureSampleCount = 0;
   ArrayResize(m_driftHistory, MONITOR_HISTORY_SIZE);
   m_driftHistoryCount = 0;
   m_driftMean = 0.0;
   m_driftStd = 0.0;
  }

ModelMonitor::~ModelMonitor() {}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ModelMonitor::AutoCalibrateThresholds()
  {
   if(m_totalPredictions < WARMUP_SAMPLES)
      return;
   if(m_driftHistoryCount > 20)
     {
      double sum = 0.0, sumSq = 0.0;
      for(int i = 0; i < m_driftHistoryCount; i++)
        {
         sum += m_driftHistory[i];
         sumSq += m_driftHistory[i]*m_driftHistory[i];
        }
      m_driftMean = sum / m_driftHistoryCount;
      double variance = (sumSq / m_driftHistoryCount) - (m_driftMean * m_driftMean);
      if(variance > 0)
         m_driftStd = MathSqrt(variance);
      else
         m_driftStd = 0.1;
      m_stats.driftThreshold = m_driftMean + 2.0 * m_driftStd;
      if(m_stats.driftThreshold < 0.1)
         m_stats.driftThreshold = 0.1;
     }
   if(m_totalPredictions > 30)
     {
      double acc = m_stats.accuracy;
      if(acc > 0.4)
        {
         m_stats.performanceThreshold = acc * 0.85;
         if(m_stats.performanceThreshold < 0.45)
            m_stats.performanceThreshold = 0.45;
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ModelMonitor::RecordPrediction(double predictedDirection, double onnxProbability, double knnProbability, double smcConfidence)
  {
   PredictionRecord record;
   record.timestamp = TimeCurrent();
   record.predictedDirection = predictedDirection;
   record.onnxProbability = onnxProbability;
   record.knnProbability = knnProbability;
   record.smcConfidence = smcConfidence;
   record.actualDirection = 0.0;
   record.wasCorrect = false;
   record.predictionError = 0.0;
   m_predictionHistory[m_historyIndex] = record;
   m_historyIndex = (m_historyIndex + 1) % MONITOR_HISTORY_SIZE;
   if(m_totalPredictions < MONITOR_HISTORY_SIZE)
      m_totalPredictions++;
   UpdateStatistics();
   AutoCalibrateThresholds();
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ModelMonitor::RecordActualOutcome(double actualDirection)
  {
   if(m_totalPredictions == 0)
      return;
   int lastIdx = (m_historyIndex - 1 + MONITOR_HISTORY_SIZE) % MONITOR_HISTORY_SIZE;
   m_predictionHistory[lastIdx].actualDirection = actualDirection;
   m_predictionHistory[lastIdx].predictionError = MathAbs(m_predictionHistory[lastIdx].predictedDirection - actualDirection);
   if(m_predictionHistory[lastIdx].predictedDirection * actualDirection > 0)
      m_predictionHistory[lastIdx].wasCorrect = true;
   UpdateStatistics();
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ModelMonitor::UpdateFeatureBaseline(const double &features[])
  {
   int featureCount = MathMin(ArraySize(features), 12);
   if(featureCount == 0)
      return;
   for(int i = 0; i < featureCount; i++)
     {
      if(m_featureSampleCount == 0)
         m_featureBaseline[i] = features[i];
      else
        {
         double alpha = 0.05;
         m_featureBaseline[i] = alpha * features[i] + (1.0 - alpha) * m_featureBaseline[i];
        }
     }
   m_featureSampleCount++;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ModelMonitor::RecordCurrentFeatures(const double &features[])
  {
   int featureCount = MathMin(ArraySize(features), 12);
   if(featureCount == 0)
      return;
   for(int i = 0; i < featureCount; i++)
      m_featureCurrent[i] = features[i];
   DetectFeatureDrift(features);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ModelMonitor::DetectFeatureDrift(const double &features[])
  {
   if(m_featureSampleCount < 20)
      return;
   int featureCount = MathMin(ArraySize(features), 12);
   double totalDrift = 0.0;
   for(int i = 0; i < featureCount; i++)
      if(m_featureBaseline[i] != 0.0)
        {
         double relativeChange = MathAbs(features[i] - m_featureBaseline[i]) / MathAbs(m_featureBaseline[i] + 1e-9);
         totalDrift += relativeChange;
        }
   m_stats.driftScore = totalDrift / featureCount;
   if(m_driftHistoryCount < MONITOR_HISTORY_SIZE)
     {
      m_driftHistory[m_driftHistoryCount] = m_stats.driftScore;
      m_driftHistoryCount++;
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ModelMonitor::UpdateStatistics()
  {
   if(m_totalPredictions == 0)
      return;
   int correct = 0, withOutcome = 0;
   for(int i = 0; i < m_totalPredictions; i++)
      if(m_predictionHistory[i].actualDirection != 0.0)
        { withOutcome++; if(m_predictionHistory[i].wasCorrect) correct++; }
   m_stats.totalPredictions = m_totalPredictions;
   m_stats.correctPredictions = correct;
   if(withOutcome > 0)
      m_stats.accuracy = (double)correct / withOutcome;
   m_stats.driftScore = CalculateDriftScore();
   m_stats.lastUpdate = TimeCurrent();
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double ModelMonitor::CalculateDriftScore()
  {
   if(m_totalPredictions < 20)
      return 0.0;
   double sumError = 0.0, sumSqError = 0.0;
   int validRecords = 0;
   for(int i = 0; i < m_totalPredictions; i++)
      if(m_predictionHistory[i].actualDirection != 0.0)
        { double error = m_predictionHistory[i].predictionError; sumError += error; sumSqError += error*error; validRecords++; }
   if(validRecords == 0)
      return 0.0;
   double avgError = sumError / validRecords;
   double variance = (sumSqError / validRecords) - (avgError*avgError);
   double stdDev = MathSqrt(MathMax(0.0, variance));
   m_stats.avgPredictionError = avgError;
   m_stats.predictionStdDev = stdDev;
   return stdDev;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool ModelMonitor::IsModelDegraded()
  {
   if(m_totalPredictions < WARMUP_SAMPLES)
      return false;
   if(!m_baselinesEstablished)
     {
      SetBaselineAccuracy(m_stats.accuracy);
      SetBaselineDriftScore(m_stats.driftScore);
      return false;
     }
   return IsPerformanceDegraded() || IsDataDriftDetected();
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool ModelMonitor::IsPerformanceDegraded()
  { return (m_totalPredictions >= WARMUP_SAMPLES) && (m_stats.accuracy < m_stats.performanceThreshold); }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool ModelMonitor::IsDataDriftDetected()
  { return (m_totalPredictions >= WARMUP_SAMPLES) && (m_stats.driftScore > m_stats.driftThreshold); }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ModelMonitor::SetBaselineAccuracy(double accuracy) { m_baselineAccuracy = accuracy; m_baselinesEstablished = true; }
void ModelMonitor::SetBaselineDriftScore(double driftScore) { m_baselineDriftScore = driftScore; }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool ModelMonitor::SaveState(string fileName)
  {
   int handle = FileOpen(fileName, FILE_BIN | FILE_WRITE);
   if(handle == INVALID_HANDLE)
      return false;
   FileWriteInteger(handle, m_totalPredictions);
   FileWriteInteger(handle, m_historyIndex);
   FileWriteInteger(handle, m_driftHistoryCount);
   FileWriteArray(handle, m_driftHistory, 0, m_driftHistoryCount);
   FileWriteDouble(handle, m_driftMean);
   FileWriteDouble(handle, m_driftStd);
   FileWriteDouble(handle, m_stats.driftThreshold);
   FileWriteDouble(handle, m_stats.performanceThreshold);
   for(int i = 0; i < MONITOR_HISTORY_SIZE; i++)
     {
      FileWriteDouble(handle, m_predictionHistory[i].timestamp);
      FileWriteDouble(handle, m_predictionHistory[i].predictedDirection);
      FileWriteDouble(handle, m_predictionHistory[i].onnxProbability);
      FileWriteDouble(handle, m_predictionHistory[i].knnProbability);
      FileWriteDouble(handle, m_predictionHistory[i].smcConfidence);
      FileWriteDouble(handle, m_predictionHistory[i].actualDirection);
      FileWriteInteger(handle, m_predictionHistory[i].wasCorrect);
      FileWriteDouble(handle, m_predictionHistory[i].predictionError);
     }
   FileWriteDouble(handle, m_baselineAccuracy);
   FileWriteDouble(handle, m_baselineDriftScore);
   FileWriteInteger(handle, m_baselinesEstablished);
   FileWriteArray(handle, m_featureBaseline);
   FileWriteArray(handle, m_featureCurrent);
   FileWriteInteger(handle, m_featureSampleCount);
   FileClose(handle);
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool ModelMonitor::LoadState(string fileName)
  {
   if(!FileIsExist(fileName))
      return false;
   int handle = FileOpen(fileName, FILE_BIN | FILE_READ);
   if(handle == INVALID_HANDLE)
      return false;
   m_totalPredictions = FileReadInteger(handle);
   m_historyIndex = FileReadInteger(handle);
   m_driftHistoryCount = FileReadInteger(handle);
   FileReadArray(handle, m_driftHistory, 0, m_driftHistoryCount);
   m_driftMean = FileReadDouble(handle);
   m_driftStd = FileReadDouble(handle);
   m_stats.driftThreshold = FileReadDouble(handle);
   m_stats.performanceThreshold = FileReadDouble(handle);
   for(int i = 0; i < MONITOR_HISTORY_SIZE; i++)
     {
      m_predictionHistory[i].timestamp = (datetime)FileReadDouble(handle);
      m_predictionHistory[i].predictedDirection = FileReadDouble(handle);
      m_predictionHistory[i].onnxProbability = FileReadDouble(handle);
      m_predictionHistory[i].knnProbability = FileReadDouble(handle);
      m_predictionHistory[i].smcConfidence = FileReadDouble(handle);
      m_predictionHistory[i].actualDirection = FileReadDouble(handle);
      m_predictionHistory[i].wasCorrect = (bool)FileReadInteger(handle);
      m_predictionHistory[i].predictionError = FileReadDouble(handle);
     }
   m_baselineAccuracy = FileReadDouble(handle);
   m_baselineDriftScore = FileReadDouble(handle);
   m_baselinesEstablished = (bool)FileReadInteger(handle);
   FileReadArray(handle, m_featureBaseline);
   FileReadArray(handle, m_featureCurrent);
   m_featureSampleCount = FileReadInteger(handle);
   FileClose(handle);
   UpdateStatistics();
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ModelMonitor::Reset()
  {
   for(int i = 0; i < MONITOR_HISTORY_SIZE; i++)
      ZeroMemory(m_predictionHistory[i]);
   m_historyIndex = 0;
   m_totalPredictions = 0;
   m_driftHistoryCount = 0;
   m_driftMean = 0.0;
   m_driftStd = 0.0;
   ZeroMemory(m_stats);
   m_stats.lastUpdate = 0;
   m_stats.driftThreshold = 0.3;
   m_stats.performanceThreshold = 0.55;
   m_baselineAccuracy = 0.0;
   m_baselineDriftScore = 0.0;
   m_baselinesEstablished = false;
   ArrayInitialize(m_featureBaseline, 0.0);
   ArrayInitialize(m_featureCurrent, 0.0);
   m_featureSampleCount = 0;
  }

#endif // __MODELMONITOR_MQH__
//+------------------------------------------------------------------+
