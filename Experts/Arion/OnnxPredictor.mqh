//+------------------------------------------------------------------+
//|                                             OnnxPredictor.mqh    |
//|                        Arion - ONNX Dinámico 12D                 |
//|                        Soporte inicialización sin modelo          |
//|                        Autor: Alexy Hernández                    |
//|                        Versión: 1.0                              |
//|        Copyright (c) 2025 Alexy Hernández. Todos los derechos    |
//|        reservados.                                               |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernández. Todos los derechos reservados."
#property link      "https://github.com/axgeovax"
#property version   "1.0"
#property strict

#ifndef __ONNXPREDICTOR_MQH__
#define __ONNXPREDICTOR_MQH__

//+------------------------------------------------------------------+
//|                                                                  |
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

   void              CalculateStatistics(const long &data[], int total, double &mean, double &stdDev);

public:
                     OnnxPredictor(string symbol = NULL);
                    ~OnnxPredictor();

   bool              Initialize(int periods = 20, double threshold = 2.0);
   bool              Initialize(int periods, double threshold, bool loadModel);

   bool              CalculateVolumeZScore(int periods = 0);
   double            GetLastZScore() const { return m_lastZScore; }
   bool              LoadONNXModel(string filePath = "Arion\\ArionIntelligence.onnx");
   bool              ExecuteXGBoostPrediction(float &inputData[], double &probBuy, double &probSell);
   bool              IsModelLoaded() const { return m_modelLoaded; }
   int               GetInputSize() const { return m_inputSize; }
   int               GetOutputSize() const { return m_outputSize; }
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
   m_inputSize = 12;              // ← Actualizado a 12 dimensiones
   m_outputSize = 5;
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
  }

//+------------------------------------------------------------------+
//| Inicialización estándar (con carga de modelo)                     |
//+------------------------------------------------------------------+
bool OnnxPredictor::Initialize(int periods, double threshold)
  {
   return Initialize(periods, threshold, true);
  }

//+------------------------------------------------------------------+
//| Inicialización con control de carga del modelo                    |
//+------------------------------------------------------------------+
bool OnnxPredictor::Initialize(int periods, double threshold, bool loadModel)
  {
   m_zScorePeriods = (periods > 0) ? periods : 20;
   m_zScoreThreshold = (threshold > 0.0) ? threshold : 2.0;
   if(!SymbolSelect(m_symbol, true))
      return false;

   if(loadModel)
      return LoadONNXModel("Arion\\ArionIntelligence.onnx");
   else
     {
      m_modelLoaded = false;
      return true;
     }
  }

//+------------------------------------------------------------------+
//| Calcular estadísticas                                              |
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
//| Calcular Z‑Score de volumen                                        |
//+------------------------------------------------------------------+
bool OnnxPredictor::CalculateVolumeZScore(int periods)
  {
   if(periods <= 0)
      periods = m_zScorePeriods;
   long volumes[];
   if(CopyTickVolume(m_symbol, PERIOD_M1, 0, periods + 1, volumes) < periods + 1)
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

   m_lastZScore = ((double)currentVolume - mean) / stdDev;
   return (m_lastZScore > m_zScoreThreshold);
  }

//+------------------------------------------------------------------+
//| Cargar modelo ONNX (entrada 12, salida 5)                         |
//+------------------------------------------------------------------+
bool OnnxPredictor::LoadONNXModel(string filePath)
  {
   if(m_onnxHandle != 0)
     {
      OnnxRelease(m_onnxHandle);
      m_onnxHandle = 0;
      m_modelLoaded = false;
     }

   if(!FileIsExist(filePath))
     {
      Print("Error [OnnxPredictor]: ONNX model file not found: ", filePath);
      return false;
     }

   m_onnxHandle = OnnxCreate(filePath, ONNX_LOGLEVEL_INFO);
   if(m_onnxHandle == 0)
     {
      Print("Error [OnnxPredictor]: Cannot load ONNX model ", filePath);
      return false;
     }

   long inputCount = OnnxGetInputCount(m_onnxHandle);
   long outputCount = OnnxGetOutputCount(m_onnxHandle);
   if(inputCount <= 0 || outputCount <= 0)
     {
      Print("Warning [OnnxPredictor]: Model validation returned ", inputCount, "/", outputCount, ". Trying to continue...");
     }
   else
      if(inputCount != 1 || outputCount != 1)
        {
         Print("Error [OnnxPredictor]: Model must have exactly 1 input and 1 output. Inputs=", inputCount, " Outputs=", outputCount);
         OnnxRelease(m_onnxHandle);
         m_onnxHandle = 0;
         return false;
        }

// Forzar forma de entrada a {1, 12}
   long inputShape[] = {1, 12};
   if(!OnnxSetInputShape(m_onnxHandle, 0, inputShape))
     {
      Print("Error [OnnxPredictor]: Failed to set input shape.");
      OnnxRelease(m_onnxHandle);
      m_onnxHandle = 0;
      return false;
     }

// Forzar forma de salida a {1, 5}
   long outputShape[] = {1, 5};
   if(!OnnxSetOutputShape(m_onnxHandle, 0, outputShape))
     {
      Print("Error [OnnxPredictor]: Failed to set output shape.");
      OnnxRelease(m_onnxHandle);
      m_onnxHandle = 0;
      return false;
     }

   m_modelLoaded = true;
   Print("ONNX model loaded successfully: ", filePath, " (input size: 12, output size: 5)");
   return true;
  }

//+------------------------------------------------------------------+
//| Ejecutar predicción XGBoost (entrada 12, salida 5)                |
//+------------------------------------------------------------------+
bool OnnxPredictor::ExecuteXGBoostPrediction(float &inputData[], double &probBuy, double &probSell)
  {
   if(!m_modelLoaded || m_onnxHandle == 0)
      return false;
   if(ArraySize(inputData) < m_inputSize)
     {
      Print("Error [OnnxPredictor]: inputData size (", ArraySize(inputData), ") < ", m_inputSize);
      return false;
     }

   float outputData[];
   ArrayResize(outputData, m_outputSize);   // 5 elementos

   if(!OnnxRun(m_onnxHandle, ONNX_DATA_TYPE_FLOAT, inputData, outputData))
     {
      Print("Error [OnnxPredictor]: OnnxRun failed.");
      return false;
     }

// Combinar clases para obtener señales de compra/venta
   probSell = outputData[0] + outputData[1];   // clases bajistas
   probBuy  = outputData[3] + outputData[4];   // clases alcistas

// Normalizar para que sumen 1
   double total = probBuy + probSell;
   if(total > 1e-12)
     {
      probBuy  /= total;
      probSell /= total;
     }
   else
     {
      probBuy = probSell = 0.5;
     }

   return true;
  }

#endif // __ONNXPREDICTOR_MQH__
//+------------------------------------------------------------------+
