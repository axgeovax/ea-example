//+------------------------------------------------------------------+
//|                                            OnnxPredictor.mqh      |
//|                        Arion - ONNX Dinamico v2.0                  |
//|          ¡El modelo actual DEBE ser reentrenado con datos reales! |
//|                        Autor: Alexy Hernandez                    |
//|                        Version: 2.0                              |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernandez. Todos los derechos reservados."
#property link      "https://github.com/axgeovax"
#property version   "2.0"
#property strict

#ifndef __ONNXPREDICTOR_MQH__
#define __ONNXPREDICTOR_MQH__

#include "SmartMoney.mqh"             // para TrainingLabelGenerator
#include "NormalizationEngine.mqh"    // asumo que existe

//+------------------------------------------------------------------+
//| Estructura para parametros de normalizacion                       |
//+------------------------------------------------------------------+
struct NormalizationParams
  {
   double            mean[12];
   double            std[12];
  };

//+------------------------------------------------------------------+
//| Estructura para resultados de validacion                          |
//+------------------------------------------------------------------+
struct ValidationResult
  {
   bool              isValid;
   double            validityScore;
   double            featureScores[12];
   int               outlierCount;
   string            errorMessage;
  };

//+------------------------------------------------------------------+
//| Clase OnnxPredictor                                                |
//+------------------------------------------------------------------+
class OnnxPredictor
  {
private:
   string            m_symbol;
   int               m_zScorePeriods;
   double            m_zScoreThreshold;
   long              m_onnxHandle;
   bool              m_modelLoaded;
   double            m_lastZScore;
   int               m_inputSize;
   int               m_outputSize;
   NormalizationParams m_norm;
   bool              m_normLoaded;

   datetime          m_lastOnnxModTime;
   ulong             m_lastOnnxSize;

   NormalizationEngine* m_normEngine;
   bool              m_validationEnabled;
   double            m_minValidityThreshold;

   void              CalculateStatistics(const long &data[], int total, double &mean, double &stdDev);
   bool              CheckFileChanged(string filePath);
   bool              LoadNormalizationParams(string normPath);
   bool              ValidateInputData(float &inputData[], ValidationResult &result);

public:
                     OnnxPredictor(string symbol = NULL);
                    ~OnnxPredictor();

   bool              Initialize(int periods = 20, double threshold = 2.0);
   bool              Initialize(int periods, double threshold, bool loadModel);

   bool              CalculateVolumeZScore(int periods = 0, ENUM_TIMEFRAMES tf = PERIOD_M15);

   double            GetLastZScore() const { return m_lastZScore; }
   bool              LoadONNXModel(string filePath = "Arion\\ArionIntelligence.onnx",
                                   string normPath = "Arion\\ArionIntelligence.norm");
   bool              ExecuteXGBoostPrediction(float &inputData[], double &probBuy, double &probSell);
   bool              ExecuteXGBoostPredictionWithValidation(float &inputData[], double &probBuy, double &probSell, ValidationResult &validationResult);

   bool              IsModelLoaded() const { return m_modelLoaded; }
   int               GetInputSize() const { return m_inputSize; }
   int               GetOutputSize() const { return m_outputSize; }

   void              SetModelDimensions(int inputSize, int outputSize) { m_inputSize = inputSize; m_outputSize = outputSize; }
   void              EnableValidation(bool enable) { m_validationEnabled = enable; }
   void              SetMinValidityThreshold(double threshold) { m_minValidityThreshold = MathMax(0.0, MathMin(1.0, threshold)); }

   NormalizationEngine* GetNormalizationEngine() { return m_normEngine; }

   // CORREGIDO: labelGen ahora es puntero (puede ser NULL)
   bool              ExportTrainingData(string fileName, int barCount = 500,
                                        TrainingLabelGenerator *labelGen = NULL);
  };

//+------------------------------------------------------------------+
//| Constructor                                                        |
//+------------------------------------------------------------------+
OnnxPredictor::OnnxPredictor(string symbol)
  {
   m_symbol = (symbol == NULL) ? _Symbol : symbol;
   m_zScorePeriods = 20;
   m_zScoreThreshold = 2.0;
   m_lastZScore = 0.0;
   m_onnxHandle = 0;
   m_modelLoaded = false;
   m_inputSize = 12;
   m_outputSize = 5;
   m_normLoaded = false;
   ArrayInitialize(m_norm.mean, 0.0);
   ArrayInitialize(m_norm.std, 1.0);

   m_lastOnnxModTime = 0;
   m_lastOnnxSize    = 0;

   m_normEngine = new NormalizationEngine(m_symbol);
   m_validationEnabled = true;
   m_minValidityThreshold = 0.7;
  }

//+------------------------------------------------------------------+
//| Destructor                                                         |
//+------------------------------------------------------------------+
OnnxPredictor::~OnnxPredictor()
  {
   if(m_onnxHandle != 0)
     {
      OnnxRelease(m_onnxHandle);
      m_onnxHandle = 0;
      m_modelLoaded = false;
     }

   if(CheckPointer(m_normEngine) == POINTER_DYNAMIC)
     {
      delete m_normEngine;
      m_normEngine = NULL;
     }
  }

//+------------------------------------------------------------------+
//| Inicializacion estandar                                            |
//+------------------------------------------------------------------+
bool OnnxPredictor::Initialize(int periods, double threshold)
  {
   return Initialize(periods, threshold, true);
  }

//+------------------------------------------------------------------+
//| Inicializacion con control de carga del modelo                    |
//+------------------------------------------------------------------+
bool OnnxPredictor::Initialize(int periods, double threshold, bool loadModel)
  {
   m_zScorePeriods = (periods > 0) ? periods : 20;
   m_zScoreThreshold = (threshold > 0.0) ? threshold : 2.0;
   if(!SymbolSelect(m_symbol, true))
      return false;

   if(loadModel)
     {
      if(!LoadONNXModel("Arion\\ArionIntelligence.onnx", "Arion\\ArionIntelligence.norm"))
         return false;
     }
   else
     {
      m_modelLoaded = false;
      m_normLoaded = false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Calcular estadisticas (media y desviacion estandar)               |
//+------------------------------------------------------------------+
void OnnxPredictor::CalculateStatistics(const long &data[], int total,
                                        double &mean, double &stdDev)
  {
   if(total == 0)
     {
      mean = 0.0;
      stdDev = 0.0;
      return;
     }
   double sum = 0.0;
   for(int i = 0; i < total; i++)
      sum += (double)data[i];
   mean = sum / total;
   double sumSq = 0.0;
   for(int i = 0; i < total; i++)
     {
      double diff = (double)data[i] - mean;
      sumSq += diff * diff;
     }
   stdDev = MathSqrt(sumSq / total);
  }

//+------------------------------------------------------------------+
//| Calcular Z-Score de volumen                                       |
//+------------------------------------------------------------------+
bool OnnxPredictor::CalculateVolumeZScore(int periods = 0, ENUM_TIMEFRAMES tf = PERIOD_M15)
  {
   if(periods <= 0)
      periods = m_zScorePeriods;

   long volumes[];
   if(CopyTickVolume(m_symbol, tf, 0, periods + 1, volumes) < periods + 1)
      return false;
   ArraySetAsSeries(volumes, true);

   long currentVolume = volumes[0];
   long history[];
   ArrayResize(history, periods);
   for(int i = 0; i < periods; i++)
      history[i] = volumes[i + 1];

   double mean, stdDev;
   CalculateStatistics(history, periods, mean, stdDev);
   if(stdDev == 0.0)
     {
      m_lastZScore = 0.0;
      return false;
     }

   double zScoreM15 = ((double)currentVolume - mean) / stdDev;
   bool anomalyM15 = (zScoreM15 > m_zScoreThreshold);

   if(anomalyM15 && tf == PERIOD_M15)
     {
      long volumesH4[];
      if(CopyTickVolume(m_symbol, PERIOD_H4, 0, periods + 1, volumesH4) >= periods + 1)
        {
         ArraySetAsSeries(volumesH4, true);
         long currentVolH4 = volumesH4[0];
         long historyH4[];
         ArrayResize(historyH4, periods);
         for(int i = 0; i < periods; i++)
            historyH4[i] = volumesH4[i + 1];

         double meanH4, stdDevH4;
         CalculateStatistics(historyH4, periods, meanH4, stdDevH4);
         if(stdDevH4 > 0.0)
           {
            double zScoreH4 = ((double)currentVolH4 - meanH4) / stdDevH4;
            if(zScoreH4 < m_zScoreThreshold)
              {
               m_lastZScore = 0.0;
               return false;
              }
           }
        }
     }

   m_lastZScore = zScoreM15;
   return anomalyM15;
  }

//+------------------------------------------------------------------+
//| Verifica si el archivo cambio (fecha de modificacion o tamano)    |
//+------------------------------------------------------------------+
bool OnnxPredictor::CheckFileChanged(string filePath)
  {
   if(!FileIsExist(filePath))
      return false;

   datetime currentModTime = (datetime)FileGetInteger(filePath, FILE_MODIFY_DATE, false);
   ulong    currentSize    = FileGetInteger(filePath, FILE_SIZE, false);

   if(m_lastOnnxModTime != currentModTime || m_lastOnnxSize != currentSize)
     {
      m_lastOnnxModTime = currentModTime;
      m_lastOnnxSize    = currentSize;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Cargar parametros de normalizacion                                |
//+------------------------------------------------------------------+
bool OnnxPredictor::LoadNormalizationParams(string normPath)
  {
   if(!FileIsExist(normPath))
     {
      Print("Archivo de normalizacion no encontrado: ", normPath, ". Se usaran valores por defecto.");
      m_normLoaded = false;
      return false;
     }

   int handle = FileOpen(normPath, FILE_BIN | FILE_READ);
   if(handle == INVALID_HANDLE)
     {
      Print("Error al abrir ", normPath);
      return false;
     }

   double means[12], stds[12];
   if(FileReadArray(handle, means, 0, 12) != 12 ||
      FileReadArray(handle, stds, 0, 12) != 12)
     {
      Print("Error: formato incorrecto en ", normPath);
      FileClose(handle);
      return false;
     }

   FileClose(handle);

   for(int i=0; i<12; i++)
     {
      m_norm.mean[i] = means[i];
      if(stds[i] > 0.0)
         m_norm.std[i] = stds[i];
      else
        {
         Print("Advertencia: desviacion estandar <= 0 en dimension ", i, ". Se usara 1.0.");
         m_norm.std[i] = 1.0;
        }
     }
   m_normLoaded = true;
   Print("Normalizacion cargada desde ", normPath);

   if(CheckPointer(m_normEngine) == POINTER_DYNAMIC)
     {
      m_normEngine.LoadParams(normPath);
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Cargar modelo ONNX                                                |
//+------------------------------------------------------------------+
bool OnnxPredictor::LoadONNXModel(string filePath = "Arion\\ArionIntelligence.onnx",
                                  string normPath = "Arion\\ArionIntelligence.norm")
  {
   if(m_onnxHandle != 0)
     {
      OnnxRelease(m_onnxHandle);
      m_onnxHandle = 0;
      m_modelLoaded = false;
     }

   if(!FileIsExist(filePath))
     {
      Print("Modelo ONNX no encontrado: ", filePath);
      return false;
     }

   if(CheckFileChanged(filePath))
      Print("Archivo ONNX modificado, se recargara.");

   m_onnxHandle = OnnxCreate(filePath, ONNX_LOGLEVEL_INFO);
   if(m_onnxHandle == 0)
     {
      Print("Error al crear el modelo ONNX");
      return false;
     }

   Print("Usando dimensiones: input=", m_inputSize, ", output=", m_outputSize);

   long inputCount = OnnxGetInputCount(m_onnxHandle);
   long outputCount = OnnxGetOutputCount(m_onnxHandle);
   if(inputCount != 1 || outputCount != 1)
     {
      Print("Error: el modelo debe tener exactamente 1 entrada y 1 salida. Entradas=", inputCount, " Salidas=", outputCount);
      OnnxRelease(m_onnxHandle);
      m_onnxHandle = 0;
      return false;
     }

   long inputShape[] = {1, m_inputSize};
   if(!OnnxSetInputShape(m_onnxHandle, 0, inputShape))
     {
      Print("Error al asignar forma de entrada {1, ", m_inputSize, "}");
      OnnxRelease(m_onnxHandle);
      m_onnxHandle = 0;
      return false;
     }

   long outputShape[] = {1, m_outputSize};
   if(!OnnxSetOutputShape(m_onnxHandle, 0, outputShape))
     {
      Print("Error al asignar forma de salida {1, ", m_outputSize, "}");
      OnnxRelease(m_onnxHandle);
      m_onnxHandle = 0;
      return false;
     }

   LoadNormalizationParams(normPath);

   if(m_outputSize != 5)
     {
      Print("CRITICAL ERROR: ONNX model output size is ", m_outputSize, ". Arion requires exactly 5 classes.");
      OnnxRelease(m_onnxHandle);
      m_onnxHandle = 0;
      m_modelLoaded = false;
      return false;
     }

   m_modelLoaded = true;
   Print("Modelo ONNX cargado correctamente: ", filePath, " (input=", m_inputSize, ", output=", m_outputSize, ")");
   return true;
  }

//+------------------------------------------------------------------+
//| Valida datos de entrada antes de procesar                         |
//+------------------------------------------------------------------+
bool OnnxPredictor::ValidateInputData(float &inputData[], ValidationResult &result)
  {
   ArrayInitialize(result.featureScores, 0.0);
   result.isValid = true;
   result.validityScore = 1.0;
   result.outlierCount = 0;
   result.errorMessage = "";

   if(ArraySize(inputData) < m_inputSize)
     {
      result.isValid = false;
      result.validityScore = 0.0;
      result.errorMessage = "Insufficient input data";
      return false;
     }

   double doubleData[12];
   for(int i = 0; i < m_inputSize; i++)
     {
      doubleData[i] = (double)inputData[i];
     }

   if(CheckPointer(m_normEngine) == POINTER_DYNAMIC && m_normEngine.IsParamsLoaded())
     {
      if(!m_normEngine.ValidateFeatureRange(doubleData, result.featureScores))
        {
         result.isValid = false;
         result.validityScore = m_normEngine.GetValidatedScore(doubleData);

         for(int i = 0; i < m_inputSize; i++)
           {
            if(result.featureScores[i] < 0.5)
               result.outlierCount++;
           }

         if(result.outlierCount > 3)
           {
            result.errorMessage = "Too many outliers: " + IntegerToString(result.outlierCount);
           }
        }
      else
        {
         result.validityScore = m_normEngine.GetValidatedScore(doubleData);
        }
     }
   else
     {
      for(int i = 0; i < m_inputSize; i++)
        {
         if(!MathIsValidNumber(inputData[i]))
           {
            result.isValid = false;
            result.featureScores[i] = 0.0;
            result.outlierCount++;
           }
         else
           {
            result.featureScores[i] = 1.0;
           }
        }

      if(result.outlierCount > 0)
        {
         result.isValid = false;
         result.validityScore = 1.0 - (double)result.outlierCount / m_inputSize;
         result.errorMessage = "Non-finite values detected";
        }
     }

   if(result.isValid && result.validityScore < m_minValidityThreshold)
     {
      result.isValid = false;
      result.errorMessage = "Validity score below threshold: " + DoubleToString(result.validityScore, 3);
     }

   return result.isValid;
  }

//+------------------------------------------------------------------+
//| Ejecutar prediccion XGBoost                                       |
//+------------------------------------------------------------------+
bool OnnxPredictor::ExecuteXGBoostPrediction(float &inputData[], double &probBuy, double &probSell)
  {
   if(!m_modelLoaded || m_onnxHandle == 0)
      return false;

   if(m_outputSize != 5)
     {
      Print("CRITICAL ERROR: ONNX model incompatible. Expected 5 classes, got ", m_outputSize);
      return false;
     }

   int featureCount = m_inputSize;
   if(ArraySize(inputData) < featureCount)
     {
      Print("Error: inputData size (", ArraySize(inputData), ") < expected ", featureCount);
      return false;
     }

   if(!m_normLoaded)
     {
      Print("Error: normalization parameters not loaded. Cannot run prediction.");
      return false;
     }

   float normalizedData[];
   ArrayResize(normalizedData, featureCount);
   for(int i = 0; i < featureCount; i++)
     {
      double val = inputData[i];
      val = (val - m_norm.mean[i]) / m_norm.std[i];
      normalizedData[i] = (float)val;
     }

   float outputData[];
   ArrayResize(outputData, m_outputSize);

   if(!OnnxRun(m_onnxHandle, ONNX_DATA_TYPE_FLOAT, normalizedData, outputData))
     {
      Print("Error en OnnxRun");
      return false;
     }

   double totalProb = outputData[0] + outputData[1] + outputData[2] + outputData[3] + outputData[4];
   if(totalProb > 0.0)
     {
      probSell = (outputData[0] + outputData[1]) / totalProb;
      probBuy  = (outputData[3] + outputData[4]) / totalProb;
     }
   else
     {
      probSell = 0.5;
      probBuy  = 0.5;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Ejecutar prediccion con validacion                                 |
//+------------------------------------------------------------------+
bool OnnxPredictor::ExecuteXGBoostPredictionWithValidation(float &inputData[], double &probBuy, double &probSell, ValidationResult &validationResult)
  {
   probBuy = 0.5;
   probSell = 0.5;

   if(!m_modelLoaded || m_onnxHandle == 0)
     {
      validationResult.isValid = false;
      validationResult.errorMessage = "Model not loaded";
      return false;
     }

   if(m_validationEnabled)
     {
      if(!ValidateInputData(inputData, validationResult))
        {
         if(validationResult.errorMessage == "")
            validationResult.errorMessage = "Input validation failed";
         Print("ONNX Input validation failed: ", validationResult.errorMessage, " Score: ", validationResult.validityScore);
         return false;
        }
     }

   if(!ExecuteXGBoostPrediction(inputData, probBuy, probSell))
     {
      validationResult.isValid = false;
      validationResult.errorMessage = "ONNX execution failed";
      return false;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Exporta datos historicos en formato CSV para reentrenar ONNX     |
//| (Etiquetas reales via TrainingLabelGenerator si se proporciona)  |
//+------------------------------------------------------------------+
bool OnnxPredictor::ExportTrainingData(string fileName, int barCount = 500,
                                       TrainingLabelGenerator *labelGen = NULL)
  {
   MqlRates rates[];
   int copied = CopyRates(m_symbol, PERIOD_M15, 0, barCount + FUTURE_BARS + 20, rates);
   if(copied < barCount + FUTURE_BARS + 20)
     {
      Print("No hay suficientes barras para exportar");
      return false;
     }
   ArraySetAsSeries(rates, true);

// Preparar handles de indicadores (para calcular adx, rsi, atr)
   int atrHandle = iATR(m_symbol, PERIOD_M15, 14);
   int adxHandle = iADX(m_symbol, PERIOD_M15, 14);
   int rsiHandle = iRSI(m_symbol, PERIOD_M15, 14, PRICE_CLOSE);
   if(atrHandle==INVALID_HANDLE || adxHandle==INVALID_HANDLE || rsiHandle==INVALID_HANDLE)
     {
      Print("Error creando indicadores");
      return false;
     }

   double atrBuf[], adxBuf[], rsiBuf[];
   int atrCopied = CopyBuffer(atrHandle, 0, 0, barCount+FUTURE_BARS+20, atrBuf);
   int adxCopied = CopyBuffer(adxHandle, 0, 0, barCount+FUTURE_BARS+20, adxBuf);
   int rsiCopied = CopyBuffer(rsiHandle, 0, 0, barCount+FUTURE_BARS+20, rsiBuf);
   IndicatorRelease(atrHandle);
   IndicatorRelease(adxHandle);
   IndicatorRelease(rsiHandle);

   ArraySetAsSeries(atrBuf, true);
   ArraySetAsSeries(adxBuf, true);
   ArraySetAsSeries(rsiBuf, true);

   if(atrCopied < 14 || adxCopied < 14 || rsiCopied < 14)
     { Print("Datos insuficientes en indicadores"); return false; }

   int handle = FileOpen(fileName, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return false;

   FileWrite(handle, "slope,atr,momentum,volFlow,adx,rsi,deltaVol,spreadDev,smcRatio,relStrength,normVolatility,volRatio,direction,futureReturn,time");

// SmartMoney para smcRatio
   SmartMoney smc(m_symbol);
   smc.Initialize();

   int max_i = MathMin(barCount, MathMin(atrCopied-1, MathMin(adxCopied-1, rsiCopied-1)));
   if(max_i < 20 + FUTURE_BARS)
      return false;

   for(int i = max_i; i >= 20 + FUTURE_BARS; i--)
     {
      double atr = atrBuf[i];
      if(atr == 0.0)
         continue;

      double adx = adxBuf[i];
      double rsi = rsiBuf[i];

      // Pendiente (20 barras)
      double sumX=0, sumY=0, sumXY=0, sumX2=0;
      for(int k=0; k<20; k++)
        {
         double y = rates[i+1+k].close;
         sumX  += k;
         sumY  += y;
         sumXY += k * y;
         sumX2 += k * k;
        }
      double den = 20.0*sumX2 - sumX*sumX;
      double slope = (MathAbs(den) > 1e-12) ? (20.0*sumXY - sumX*sumY) / den : 0.0;

      double close_i   = rates[i].close;
      double close_past = rates[i+20].close;
      double momentum = (close_i - close_past) / (atr * 20.0 + 0.0001);

      long tickVol_i = rates[i].tick_volume;
      double close_prev = rates[i+1].close;
      double volFlow = (tickVol_i * (close_i - close_prev)) / (atr * close_i + 0.0001);

      // deltaVol
      double avgVol = 0;
      for(int k=0; k<20; k++)
         avgVol += (double)rates[i+1+k].tick_volume;
      avgVol /= 20.0;
      double deltaVol = (avgVol > 0) ? ((double)tickVol_i - avgVol) / avgVol : 0.0;

      // spreadDev (simplificado)
      long spread = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
      double spreadDev = (spread > 0) ? (spread - (double)spread) / spread : 0.0;

      // smcRatio
      double smcRatio = smc.GetOBMitigationRatio(close_i, true);

      // relStrength (M15 vs H4)
      int h4Shift = iBarShift(m_symbol, PERIOD_H4, rates[i].time, false);
      double relStrength = 0;
        {
         double maH4[];
         if(CopyClose(m_symbol, PERIOD_H4, h4Shift, 1, maH4) == 1)
            relStrength = (close_i - maH4[0]) / (atr + 1e-9);
        }

      double normVolatility = atr / close_i;

      // volRatio (M1/H4)
      double volRatio = 1.0;
      int atrM1 = iATR(m_symbol, PERIOD_M1, 14);
      int atrH4 = iATR(m_symbol, PERIOD_H4, 14);
      if(atrM1 != INVALID_HANDLE && atrH4 != INVALID_HANDLE)
        {
         int m1Shift = iBarShift(m_symbol, PERIOD_M1, rates[i].time, false);
         double m1[], h4[];
         if(CopyBuffer(atrM1, 0, m1Shift, 1, m1)==1 && CopyBuffer(atrH4, 0, h4Shift, 1, h4)==1 && h4[0]!=0.0)
            volRatio = m1[0] / h4[0];
         IndicatorRelease(atrM1);
         IndicatorRelease(atrH4);
        }

      // Retorno futuro
      double futureReturn = (rates[i - FUTURE_BARS].close - close_i) / close_i;
      double direction = (labelGen != NULL) ? labelGen.GetLabelForReturn(futureReturn) : 0.0;

      FileWrite(handle, StringFormat("%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.1f,%.10f,%d",
                                     slope, atr, momentum, volFlow, adx, rsi, deltaVol, spreadDev, smcRatio, relStrength, normVolatility, volRatio,
                                     direction, futureReturn, (long)rates[i].time));
     }

   FileClose(handle);
   Print("Datos de entrenamiento exportados a ", fileName);
   return true;
  }

#endif // __ONNXPREDICTOR_MQH__
