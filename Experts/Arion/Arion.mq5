//+------------------------------------------------------------------+
//|                                                     Arion.mq5    |
//|                        Arion - EA Multidivisa                    |
//|        * Log de cierres, limite de lote, rutas fijas             |
//|        * Autoentrenamiento integrado (deteccion + aviso)         |
//|        * Recarga ONNX reactivada                                 |
//|        * KNN ahora entrena con etiquetas reales (futuro)        |
//|                        Autor: Alexy Hernandez                    |
//|                        Version: 1.1                              |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernandez. Todos los derechos reservados."
#property link      "https://github.com/axgeovax"
#property version   "1.1"
#property strict
#resource "ArionIntelligence.onnx" as uchar onnx_resource_data[]

#include "RiskManager.mqh"
#include "SmartMoney.mqh"
#include "Executor.mqh"
#include "OnnxPredictor.mqh"
#include "KnnClassifier.mqh"
#include "SignalFilter.mqh"
#include "CorrelationEngine.mqh"
#include "GlobalRiskManager.mqh"
#include "NewsFilter.mqh"
#include "Logger.mqh"
#include "Dashboard.mqh"
#include "Metrics.mqh"
#include "AutoTrainManager.mqh"
#include "ModelMonitor.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input bool   InpEnableAll            = true;   // Enable all symbols
input double InpRiskPercentage       = 1.0;    // Risk per trade
input double InpMaxSafetyFactor      = 2.0;    // Max safety margin factor (1.0-3.0)
input bool   InpUseSessionFilter     = false;  // Use trading session filter
input string InpSessionStart         = "08:00"; // Session start time (server time)
input string InpSessionEnd           = "20:00"; // Session end time (server time)
input double InpTrailATRMultiplier   = 0.0;    // Trailing stop ATR multiplier (0=use pips)
input double InpMaxExposureCurrency   = 0.0;    // Max exposure per currency (0=disabled)
input double InpMaxVolatilityRatio    = 5.0;    // Max volatility ratio for emergency close
input double InpRetrainOnDegradation  = 0.0;    // Auto-retrain on model degradation (0=disabled)
input double InpATRMultiplierSL      = 8.0;    // SL multiplier
input double InpRRRatio              = 2.5;    // Risk/Reward ratio
input int    InpMaxSpreadPoints      = 50;     // Max spread
input int    InpMaxTradesPerSymbol   = 2;      // Max trades/symbol
input int    InpTimerMilliseconds    = 100;    // Timer interval
input double InpWeightONNX           = 35.0;   // ONNX weight
input double InpWeightKNN            = 30.0;   // KNN weight
input double InpWeightSMC            = 25.0;   // SMC weight
input double InpWeightContext        = 10.0;   // Context weight
input double InpApprovalThreshold    = 75.0;   // Signal threshold
input int    InpMinPipsDisplacement  = 10;     // Min stop distance
input double InpMaxDailyLossPercent  = 3.0;    // Daily loss limit
input int    InpMaxGlobalTrades      = 4;      // Max all trades
input double InpAccountTrailingStop  = 8.0;    // Account trail stop
input bool   InpCloseAllOnStop       = false;  // Close all on stop
input string InpNewsCSVPath          = "Arion\\News.csv"; // News file
input string InpNewsApiUrl           = "";     // News API URL
input int    InpMinNewsImpact        = 2;      // Min news impact
input int    InpMinutesBeforeNews    = 10;     // Minutes before news
input int    InpMinutesAfterNews     = 10;     // Minutes after news
input double InpNewsSpreadFactor     = 0.5;    // News spread factor
// Log file path is now fixed: Arion\\MONITOR\\Log.csv
input bool   InpEnablePush           = true;   // Push alerts
input bool   InpEnableEmail          = false;  // Email alerts
input string InpDestEmail            = "";     // Alert email
input string InpEmailSubject         = "Arion"; // Email subject
input int    InpAsyncOrderTimeout    = 30;     // Order timeout
input int    InpMondayCooldownMinutes = 0;     // Monday cooldown
input double InpMaxLot               = 0.02;   // Max lot per trade
input bool   InpActivateTrailing     = true;   // Trailing stop
input double InpTrailStartRatio      = 1.5;    // Trail start ratio
input double InpTrailDistancePips    = 60.0;   // Trail distance
input double InpTrailStepPips        = 5.0;    // Trail step
input string InpPythonPath           = "python.exe"; // Python path
input int    InpAutoSaveMinutes      = 30;     // Autosave interval
input bool   InpStrictValidation     = false;  // Strict validation
input bool   InpShowPythonWindow     = false;  // Show Python window

//+------------------------------------------------------------------+
//| Data Guard                                                        |
//+------------------------------------------------------------------+
bool     g_HistoryOK[10];
datetime g_LastHistoryCheck[10];

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool VerifySymbolHistory(string symbol, int idx, ENUM_TIMEFRAMES tf, int min_bars)
  {
   if(g_LastHistoryCheck[idx] != 0 && TimeCurrent() - g_LastHistoryCheck[idx] < 60)
      return g_HistoryOK[idx];
   int bars = Bars(symbol, tf);
   if(bars < min_bars)
     {
      SeriesInfoInteger(symbol, tf, SERIES_SYNCHRONIZED);
      bars = Bars(symbol, tf);
     }
   g_HistoryOK[idx] = (bars >= min_bars);
   g_LastHistoryCheck[idx] = TimeCurrent();
   return g_HistoryOK[idx];
  }

string g_Assets[] = {"AUDUSD","EURGBP","EURUSD","GBPUSD","NZDUSD",
                     "USDCAD","USDJPY","AUDJPY"
                    };
int    g_TotalAssets = 8;
ENUM_TIMEFRAMES g_TFMacro  = PERIOD_H4,
                g_TFZone   = PERIOD_M15,
                g_TFTrigger = PERIOD_M1;

RiskManager*        g_RiskManager[];
SmartMoney*         g_SmcAnalyzer[];
Executor*           g_Executor[];
OnnxPredictor*      g_StatisticalFilter[];
KnnClassifier*      g_KnnClassifier[];
SignalFilter*       g_SignalFilter[];
ModelMonitor*       g_ModelMonitor[];
TrainingLabelGenerator* g_LabelGen[];  // NUEVO: generador de etiquetas reales
datetime            g_LastAutoRetrainTime = 0;

CorrelationEngine*  g_CorrelationEngine;
GlobalRiskManager*  g_GlobalRiskManager;
NewsFilter*         g_NewsFilter;
Dashboard*          g_Dashboard;
bool                g_DashboardCreated = false;

datetime g_LastBarTimeMacro[], g_LastBarTimeZona[], g_LastBarTimeGatillo[];
int      g_HandleATR_M1[], g_HandleATR_M15[], g_HandleATR_H4[];

datetime g_LastCalcBarTime[10];
double   g_LastCalcPrice[10];
double   g_LastProbONNX[10];
double   g_LastProbKNN[10];
bool     g_LastMitigatedZone[10];
double   g_LastMitigationRatio[10];
double   g_LastMacroDirection[10];
datetime g_LastBECheck[10];

TradeResult g_Trades[];
int         g_step = 0;

datetime g_lastOnnxCheck    = 0;
datetime g_lastOnnxModTime  = 0;
double   g_lastAvgSpread    = 0.0;
int      g_lastPositionCount = 0;
datetime g_lastAutoSave     = 0;

int  g_initIndex = 0;
bool g_allSymbolsLoaded = false;

//+------------------------------------------------------------------+
//| Asegura las subcarpetas necesarias                               |
//+------------------------------------------------------------------+
void EnsureDataFolders()
  {
   EnsureArionFolder();
   FolderCreate("Arion\\SMC");
   FolderCreate("Arion\\KNN");
   FolderCreate("Arion\\MONITOR");
   FolderCreate("Arion\\DASHBOARD");
  }

//+------------------------------------------------------------------+
//| Inicializar un solo simbolo                                      |
//+------------------------------------------------------------------+
void InitSymbol(int idx)
  {
   string sym = g_Assets[idx];
   if(!SymbolSelect(sym, true))
     {
      Print("Symbol ", sym, " not available");
      return;
     }

   g_RiskManager[idx]        = new RiskManager(sym, g_CorrelationEngine);
   g_RiskManager[idx].SetMaxLot(InpMaxLot);
   g_SmcAnalyzer[idx]        = new SmartMoney(sym);
   g_Executor[idx]           = new Executor(sym, 202400 + idx, InpMaxSafetyFactor);
   g_StatisticalFilter[idx]  = new OnnxPredictor(sym);
   g_KnnClassifier[idx]      = new KnnClassifier(500, 0.002);
   g_SignalFilter[idx]       = new SignalFilter(sym);
   g_ModelMonitor[idx]       = new ModelMonitor(sym);
   g_LabelGen[idx]           = new TrainingLabelGenerator(sym, g_TFZone); // NUEVO
   g_LabelGen[idx].Initialize(FUTURE_BARS);

   g_Executor[idx].SetAsyncTimeout(InpAsyncOrderTimeout);
   g_SmcAnalyzer[idx].Initialize();
   g_SmcAnalyzer[idx].SetTrainingThresholds(10.0, 15.0, 0.1);
   g_Executor[idx].Initialize();
   g_Executor[idx].SetMinPipsDisplacement(InpMinPipsDisplacement);
   g_Executor[idx].SetNewsFilter(g_NewsFilter);
   g_Executor[idx].SetReduceLotDuringNews(false);

   g_SignalFilter[idx].SetLossCooldownBars(5);
   g_SignalFilter[idx].EnableCooldown(true);

   g_StatisticalFilter[idx].Initialize(20, 2.0, true);
   g_StatisticalFilter[idx].EnableValidation(true);
   g_StatisticalFilter[idx].SetMinValidityThreshold(0.7);

   g_KnnClassifier[idx].SetMaxSamples(1000);
   g_KnnClassifier[idx].SetAgeWeighting(true, 168.0);

   if(g_StatisticalFilter[idx].IsModelLoaded())
      g_lastOnnxModTime = MathMax(g_lastOnnxModTime, TimeCurrent());

   g_SmcAnalyzer[idx].LoadState("Arion\\SMC\\" + sym + ".bin");
   g_KnnClassifier[idx].LoadState("Arion\\KNN\\" + sym + ".bin");
   g_ModelMonitor[idx].LoadState("Arion\\MONITOR\\" + sym + ".bin");

   g_LastBarTimeMacro[idx] = g_LastBarTimeZona[idx] = g_LastBarTimeGatillo[idx] = 0;
   g_HandleATR_M1[idx]  = iATR(sym, g_TFTrigger, 14);
   g_HandleATR_M15[idx] = iATR(sym, g_TFZone, 14);
   g_HandleATR_H4[idx]  = iATR(sym, g_TFMacro, 14);

   g_LastCalcBarTime[idx] = 0;
   g_LastCalcPrice[idx] = 0.0;
   g_LastProbONNX[idx] = 0.5;
   g_LastProbKNN[idx] = 0.0;
   g_LastMitigatedZone[idx] = false;
   g_LastMitigationRatio[idx] = 0.0;
   g_LastMacroDirection[idx] = 0.0;
   g_LastHistoryCheck[idx] = 0;
   g_HistoryOK[idx] = false;
   g_LastBECheck[idx] = 0;
  }

//+------------------------------------------------------------------+
//| Utilidades                                                        |
//+------------------------------------------------------------------+
bool IsNewBarFast(string symbol, ENUM_TIMEFRAMES tf, datetime &lastBarTime)
  {
   datetime current = (datetime)SeriesInfoInteger(symbol, tf, SERIES_LASTBAR_DATE);
   if(current > lastBarTime)
     {
      lastBarTime = current;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsMondayCooldown(int minutes)
  {
   if(minutes <= 0)
      return false;
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.day_of_week != 1)
      return false;
   int secondsSinceMidnight = dt.hour * 3600 + dt.min * 60 + dt.sec;
   return (secondsSinceMidnight < minutes * 60);
  }

//+------------------------------------------------------------------+
//| Recarga el modelo ONNX si el archivo fue modificado (REACTIVADO) |
//+------------------------------------------------------------------+
void CheckAndReloadOnnx()
  {
   string onnxPath = "Arion\\ArionIntelligence.onnx";
   if(FileIsExist(onnxPath))
     {
      datetime modTime = (datetime)FileGetInteger(onnxPath, FILE_MODIFY_DATE, false);
      if(modTime > g_lastOnnxModTime)
        {
         g_lastOnnxModTime = modTime;
         for(int i=0; i<g_TotalAssets; i++)
            if(CheckPointer(g_StatisticalFilter[i]) == POINTER_DYNAMIC)
               g_StatisticalFilter[i].LoadONNXModel(onnxPath, "Arion\\ArionIntelligence.norm");
         Print("ONNX model hot-reloaded (modTime=", modTime, ")");
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SaveAllState()
  {
   EnsureDataFolders();
   for(int i=0; i<g_TotalAssets; i++)
     {
      if(CheckPointer(g_SmcAnalyzer[i]) == POINTER_DYNAMIC)
         g_SmcAnalyzer[i].SaveState("Arion\\SMC\\" + g_Assets[i] + ".bin");
      if(CheckPointer(g_KnnClassifier[i]) == POINTER_DYNAMIC)
         g_KnnClassifier[i].SaveState("Arion\\KNN\\" + g_Assets[i] + ".bin");
      if(CheckPointer(g_ModelMonitor[i]) == POINTER_DYNAMIC)
         g_ModelMonitor[i].SaveState("Arion\\MONITOR\\" + g_Assets[i] + ".bin");
     }
   g_GlobalRiskManager.SaveState("Arion\\RiskManager.bin");
  }

//+------------------------------------------------------------------+
//| Calcula las 12 caracteristicas (sin necesidad de dirActual)     |
//+------------------------------------------------------------------+
bool CalculateKNNFeatures(string sym, int i, double &slope, double &atr, double &mom, double &flow,
                          double &adx, double &rsi, double &deltaVol, double &spreadDev,
                          double &smcRatio, double &relStrength, double &normVolatility,
                          double &volRatio)
  {
   slope = g_SmcAnalyzer[i].CalculateRegressionSlope(20, PERIOD_M15);
   atr   = g_SmcAnalyzer[i].GetATR(14);
   mom   = g_SmcAnalyzer[i].CalculateMomentum(20, PERIOD_M15);
   flow  = g_SmcAnalyzer[i].CalculateVolumeFlow(20, PERIOD_M15);
   adx   = g_SmcAnalyzer[i].GetADX();
   rsi   = g_SmcAnalyzer[i].GetRSI();
   if(atr == 0.0 || adx == 0.0)
      return false;

   long tickVolM15[];
   if(CopyTickVolume(sym, PERIOD_M15, 1, 20, tickVolM15) != 20)
      return false;
   ArraySetAsSeries(tickVolM15, true);
   double avgVol = 0;
   for(int k=0;k<20;k++)
      avgVol += (double)tickVolM15[k];
   avgVol /= 20;
   if(avgVol <= 0)
      return false;
   deltaVol = ((double)tickVolM15[0] - avgVol)/avgVol;

   double avgSpread = 0;
   for(int k=0;k<20;k++)
      avgSpread += (double)SymbolInfoInteger(sym, SYMBOL_SPREAD);
   avgSpread /= 20;
   if(avgSpread <= 0)
      return false;
   long spread = SymbolInfoInteger(sym, SYMBOL_SPREAD);
   spreadDev = ((double)spread - avgSpread)/avgSpread;

   double priceMid = (SymbolInfoDouble(sym, SYMBOL_ASK)+SymbolInfoDouble(sym, SYMBOL_BID))/2;
   // Usamos la dirección macro solo para el ratio SMC, no como etiqueta
   double macroDir = g_SmcAnalyzer[i].GetMacroDirection();
   smcRatio = g_SmcAnalyzer[i].GetOBMitigationRatio(priceMid, macroDir > 0);

   double maH4[];
   if(CopyClose(sym, PERIOD_H4, 20, 1, maH4) != 1)
      return false;
   relStrength = (SymbolInfoDouble(sym, SYMBOL_BID) - maH4[0])/(atr+1e-9);

   normVolatility = atr / SymbolInfoDouble(sym, SYMBOL_BID);

   double atr1v[1], atrH4v[1];
   if(CopyBuffer(g_HandleATR_M1[i],0,0,1,atr1v)!=1 || CopyBuffer(g_HandleATR_H4[i],0,0,1,atrH4v)!=1 || atrH4v[0]==0.0)
      return false;
   volRatio = atr1v[0]/atrH4v[0];
   return true;
  }

//+------------------------------------------------------------------+
//| Validacion de inputs                                             |
//+------------------------------------------------------------------+
bool ValidateInputs()
  {
   double sumWeights = InpWeightONNX + InpWeightKNN + InpWeightSMC + InpWeightContext;
   if(MathAbs(sumWeights - 100.0) > 1.0)
     { Print("Error: Filter weights must sum 100%."); return false; }
   if(InpRiskPercentage <= 0.0 || InpRiskPercentage > 100.0)
     { Print("Error: RiskPercentage must be between 0.01 and 100."); return false; }
   if(InpATRMultiplierSL <= 0.0)
     { Print("Error: ATRMultiplierSL must be positive."); return false; }
   if(InpRRRatio <= 0.0)
     { Print("Error: RR must be positive."); return false; }
   if(InpMaxSpreadPoints < 0)
     { Print("Error: MaxSpreadPoints cannot be negative."); return false; }
   if(InpMaxTradesPerSymbol < 0)
     { Print("Error: MaxTradesPerSymbol cannot be negative."); return false; }
   if(InpMinPipsDisplacement < 0)
     { Print("Error: MinPipsDisplacement cannot be negative."); return false; }
   if(InpMaxDailyLossPercent < 0.0 || InpMaxDailyLossPercent > 100.0)
     { Print("Error: MaxDailyLossPercent must be between 0 and 100."); return false; }
   if(InpMaxGlobalTrades < 0)
     { Print("Error: MaxGlobalTrades cannot be negative."); return false; }
   if(InpAccountTrailingStop < 0.0 || InpAccountTrailingStop > 100.0)
     { Print("Error: AccountTrailingStop must be between 0 and 100."); return false; }
   if(InpAsyncOrderTimeout <= 0)
     { Print("Error: AsyncOrderTimeout must be positive."); return false; }
   if(InpMaxLot < 0.0)
     { Print("Error: MaxLot cannot be negative."); return false; }
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CheckAndRecoverFromInactivity()
  {
   string dateFile = "Arion\\LastTrainingDate.txt";
   if(!FileIsExist(dateFile))
      return;
   
   int handle = FileOpen(dateFile, FILE_READ|FILE_TXT|FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return;
   
   string lastDateStr = FileReadString(handle);
   FileClose(handle);
   
   datetime lastTraining = StringToTime(lastDateStr);
   if(lastTraining == 0)
      return;
   
   int daysInactive = (int)((TimeCurrent() - lastTraining) / 86400);
   if(daysInactive > 7)
     {
      Print("WARNING: Last training was ", daysInactive, " days ago.");
      Print("RECOMMENDATION: Execute MarketTraining.mq5 to populate historical KNN samples for better model accuracy.");
      Print("Auto-training initiated with current session data (limited samples).");
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void UpdateLastTrainingDate()
  {
   string dateFile = "Arion\\LastTrainingDate.txt";
   int handle = FileOpen(dateFile, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(handle != INVALID_HANDLE)
     {
      FileWriteString(handle, TimeToString(TimeCurrent(), TIME_DATE));
      FileClose(handle);
     }
  }

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(!ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;
   g_TotalAssets = ArraySize(g_Assets);
   if(g_TotalAssets == 0)
      return INIT_FAILED;
   CheckAndRecoverFromInactivity();

   ArrayResize(g_RiskManager, g_TotalAssets);
   ArrayResize(g_SmcAnalyzer, g_TotalAssets);
   ArrayResize(g_Executor, g_TotalAssets);
   ArrayResize(g_StatisticalFilter, g_TotalAssets);
   ArrayResize(g_KnnClassifier, g_TotalAssets);
   ArrayResize(g_SignalFilter, g_TotalAssets);
   ArrayResize(g_ModelMonitor, g_TotalAssets);
   ArrayResize(g_LabelGen, g_TotalAssets);        // NUEVO
   ArrayResize(g_LastBarTimeMacro, g_TotalAssets);
   ArrayResize(g_LastBarTimeZona, g_TotalAssets);
   ArrayResize(g_LastBarTimeGatillo, g_TotalAssets);
   ArrayResize(g_HandleATR_M1, g_TotalAssets);
   ArrayResize(g_HandleATR_M15, g_TotalAssets);
   ArrayResize(g_HandleATR_H4, g_TotalAssets);

   EnsureDataFolders();

   g_CorrelationEngine = new CorrelationEngine();
   g_CorrelationEngine.Initialize(g_Assets, g_TotalAssets);

   g_GlobalRiskManager = new GlobalRiskManager();
   g_GlobalRiskManager.Configure(InpMaxDailyLossPercent, InpMaxGlobalTrades,
                                 InpAccountTrailingStop, InpCloseAllOnStop);
   g_GlobalRiskManager.SetMagicRange(202400, g_TotalAssets);
   g_GlobalRiskManager.LoadState("Arion\\RiskManager.bin");

   g_NewsFilter = new NewsFilter();
   g_NewsFilter.Configure(InpNewsCSVPath, InpNewsApiUrl, InpMinNewsImpact,
                          InpMinutesBeforeNews, InpMinutesAfterNews, InpNewsSpreadFactor);

   Logger::Initialize("Arion\\MONITOR\\Log.csv", InpEnablePush, InpEnableEmail, InpDestEmail, InpEmailSubject);

   CreateTrainScriptIfMissing();
   EnsureInitialOnnxModel();

   g_Dashboard = new Dashboard();
   g_Dashboard.SetSpreadThresholds(InpMaxSpreadPoints, InpMaxSpreadPoints);
   g_DashboardCreated = false;

   g_lastOnnxCheck = 0;
   g_lastOnnxModTime = 0;
   g_lastAvgSpread = 0.0;
   g_lastPositionCount = 0;
   g_lastAutoSave = TimeCurrent();

   string onnxPath = "Arion\\ArionIntelligence.onnx";
   if(FileIsExist(onnxPath))
     {
      ulong onnxSize = FileGetInteger(onnxPath, FILE_SIZE, false);
      if(onnxSize > 100)
         g_lastOnnxModTime = (datetime)FileGetInteger(onnxPath, FILE_MODIFY_DATE, false);
     }

   g_initIndex = 0;
   g_allSymbolsLoaded = false;

   EventSetMillisecondTimer(InpTimerMilliseconds);
   Print("Arion v1.1 initialized (KNN with real future labels)");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   SaveAllState();
   Logger::Close();

   for(int i=0; i<g_TotalAssets; i++)
     {
      if(CheckPointer(g_SmcAnalyzer[i]) == POINTER_DYNAMIC)
         g_SmcAnalyzer[i].SaveState("Arion\\SMC\\" + g_Assets[i] + ".bin");
      if(CheckPointer(g_KnnClassifier[i]) == POINTER_DYNAMIC)
         g_KnnClassifier[i].SaveState("Arion\\KNN\\" + g_Assets[i] + ".bin");
      if(CheckPointer(g_ModelMonitor[i]) == POINTER_DYNAMIC)
         g_ModelMonitor[i].SaveState("Arion\\MONITOR\\" + g_Assets[i] + ".bin");
      if(CheckPointer(g_LabelGen[i]) == POINTER_DYNAMIC)   // NUEVO
         delete g_LabelGen[i];
     }
   if(g_Dashboard)
     {
      g_Dashboard.Remove();
      delete g_Dashboard;
     }
   for(int i=0; i<g_TotalAssets; i++)
     {
      delete g_RiskManager[i];
      delete g_SmcAnalyzer[i];
      delete g_Executor[i];
      delete g_StatisticalFilter[i];
      delete g_KnnClassifier[i];
      delete g_SignalFilter[i];
      if(CheckPointer(g_ModelMonitor[i]) == POINTER_DYNAMIC)
         delete g_ModelMonitor[i];
      if(g_HandleATR_M1[i]  != INVALID_HANDLE)
         IndicatorRelease(g_HandleATR_M1[i]);
      if(g_HandleATR_M15[i] != INVALID_HANDLE)
         IndicatorRelease(g_HandleATR_M15[i]);
      if(g_HandleATR_H4[i]  != INVALID_HANDLE)
         IndicatorRelease(g_HandleATR_H4[i]);
     }
   delete g_CorrelationEngine;
   delete g_GlobalRiskManager;
   delete g_NewsFilter;
  }

//+------------------------------------------------------------------+
//| OnTick                                                            |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!g_DashboardCreated)
     {
      g_Dashboard.Initialize(g_TotalAssets);
      ChartRedraw(0);
      g_DashboardCreated = true;
     }

   for(int i=0; i<g_TotalAssets; i++)
     {
      if(g_Assets[i] == _Symbol && CheckPointer(g_Executor[i]) == POINTER_DYNAMIC)
        {
         long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
         if(spread <= InpMaxSpreadPoints)
            g_Executor[i].ManageBreakeven(1.0, 5.0);
        }
     }
  }

//+------------------------------------------------------------------+
//| IsWithinSession - Check if current time is within trading session |
//+------------------------------------------------------------------+
bool IsWithinSession()
  {
   if(!InpUseSessionFilter)
      return true;
   
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   int currentHour = timeStruct.hour;
   int currentMin = timeStruct.min;
   
   string startParts[];
   ushort sep = ':';
   StringSplit(InpSessionStart, sep, startParts);
   int startHour = (int)StringToInteger(startParts[0]);
   int startMin = (int)StringToInteger(startParts[1]);
   int startTotal = startHour * 60 + startMin;
   
   string endParts[];
   StringSplit(InpSessionEnd, sep, endParts);
   int endHour = (int)StringToInteger(endParts[0]);
   int endMin = (int)StringToInteger(endParts[1]);
   int endTotal = endHour * 60 + endMin;
   
   int currentTotal = currentHour * 60 + currentMin;
   
   if(endTotal < startTotal)
      return currentTotal >= startTotal || currentTotal < endTotal;
   else
      return currentTotal >= startTotal && currentTotal < endTotal;
  }

//+------------------------------------------------------------------+
//| Deteccion de degradacion del modelo (sin ejecucion automatica)   |
//+------------------------------------------------------------------+
void CheckAndRetrainOnDegradation()
  {
   if(InpRetrainOnDegradation <= 0.0)
      return;
   
   if(g_LastAutoRetrainTime > 0 && TimeCurrent() - g_LastAutoRetrainTime < 3600)
      return;
   
   bool needsRetrain = false;
   for(int i = 0; i < g_TotalAssets; i++)
     {
      if(CheckPointer(g_ModelMonitor[i]) == POINTER_DYNAMIC)
        {
         double accuracy = g_ModelMonitor[i].GetAccuracy();
         double drift = g_ModelMonitor[i].GetDriftScore();
         
         if(accuracy < InpRetrainOnDegradation || drift > (1.0 - InpRetrainOnDegradation))
           {
            Print("MODEL DEGRADATION DETECTED for ", g_Assets[i], ": accuracy=", DoubleToString(accuracy,3), " drift=", DoubleToString(drift,3));
            needsRetrain = true;
            break;
           }
        }
     }
   
   if(needsRetrain)
     {
      Print("WARNING: Model degradation detected. Manual retraining is recommended.");
      Print("Execute train.py manually to retrain the ONNX model.");
      g_LastAutoRetrainTime = TimeCurrent();
     }
  }

//+------------------------------------------------------------------+
//| Cierre de emergencia por volatilidad extrema                     |
//+------------------------------------------------------------------+
void CheckEmergencyVolatilityClose()
  {
   if(InpMaxVolatilityRatio <= 0.0)
      return;
   
   for(int i = 0; i < g_TotalAssets; i++)
     {
      string sym = g_Assets[i];
      double atr1v[1], atrH4v[1];
      if(g_HandleATR_M1[i]==INVALID_HANDLE || g_HandleATR_H4[i]==INVALID_HANDLE)
         continue;
      if(CopyBuffer(g_HandleATR_M1[i],0,0,1,atr1v)!=1 || CopyBuffer(g_HandleATR_H4[i],0,0,1,atrH4v)!=1 || atrH4v[0]==0.0)
         continue;
      
      double volRatio = atr1v[0] / atrH4v[0];
      if(volRatio > InpMaxVolatilityRatio)
        {
         Print("EMERGENCY: Volatility ratio ", DoubleToString(volRatio,2), " > ", InpMaxVolatilityRatio, " for ", sym, " - closing all positions");
         
         int total = PositionsTotal();
         for(int j = total - 1; j >= 0; j--)
           {
            ulong ticket = PositionGetTicket(j);
            if(!PositionSelectByTicket(ticket))
               continue;
            if(PositionGetString(POSITION_SYMBOL) == sym)
              {
               MqlTradeRequest request;
               MqlTradeResult result;
               ZeroMemory(request);
               ZeroMemory(result);
               request.action = TRADE_ACTION_DEAL;
               request.position = ticket;
               ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
               request.type = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
               if(OrderSend(request, result))
                  Print("Closed position ", ticket, " due to extreme volatility");
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Calcula la exposicion actual a una divisa                        |
//+------------------------------------------------------------------+
double GetCurrencyExposure(string currency)
  {
   double totalRisk = 0.0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      
      string symbol = PositionGetString(POSITION_SYMBOL);
      double sl = PositionGetDouble(POSITION_SL);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double volume = PositionGetDouble(POSITION_VOLUME);
      
      if(sl == 0.0)
         continue;
      
      string base = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
      string quote = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
      
      if(base == currency || quote == currency)
        {
         double slDistance = MathAbs(sl - openPrice);
         double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
         double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
         
         if(point > 0.0)
            totalRisk += (slDistance / point) * volume * tickValue;
        }
     }
   return totalRisk;
  }

//+------------------------------------------------------------------+
//| OnTimer (logica principal)                                        |
//+------------------------------------------------------------------+
void OnTimer()
  {
   if(g_initIndex < g_TotalAssets)
     {
      InitSymbol(g_initIndex);
      g_initIndex++;
      if(g_initIndex >= g_TotalAssets)
        {
         g_allSymbolsLoaded = true;
         Print("All symbols loaded progressively.");
        }
      return;
     }

   static bool firstNewsLoaded = false;
   if(!firstNewsLoaded && g_NewsFilter != NULL)
     {
      g_NewsFilter.LoadNews();
      firstNewsLoaded = true;
     }

   if(!g_DashboardCreated)
     {
      g_Dashboard.Initialize(g_TotalAssets);
      ChartRedraw(0);
      g_DashboardCreated = true;
     }

   if(!IsWithinSession())
      return;

   CheckAndRetrainOnDegradation();
   CheckEmergencyVolatilityClose();

   static bool riskValid[10], smcValid[10], execValid[10], statValid[10], knnValid[10], sigValid[10];
   static bool cacheInitialized = false;
   if(!cacheInitialized || g_initIndex >= g_TotalAssets)
     {
      for(int i=0; i<g_TotalAssets; i++)
        {
         riskValid[i] = (CheckPointer(g_RiskManager[i]) == POINTER_DYNAMIC);
         smcValid[i]  = (CheckPointer(g_SmcAnalyzer[i]) == POINTER_DYNAMIC);
         execValid[i] = (CheckPointer(g_Executor[i]) == POINTER_DYNAMIC);
         statValid[i]= (CheckPointer(g_StatisticalFilter[i]) == POINTER_DYNAMIC);
         knnValid[i]  = (CheckPointer(g_KnnClassifier[i]) == POINTER_DYNAMIC);
         sigValid[i]  = (CheckPointer(g_SignalFilter[i]) == POINTER_DYNAMIC);
        }
      cacheInitialized = true;
     }

   for(int i=0; i<g_TotalAssets; i++)
     {
      if(riskValid[i])
         g_RiskManager[i].UpdateProperties();
      if(execValid[i])
         g_Executor[i].ClearLocks();
     }

   g_GlobalRiskManager.Update();
   bool allowSignals = g_GlobalRiskManager.CanOpenTrade();
   if(allowSignals && IsMondayCooldown(InpMondayCooldownMinutes))
      allowSignals = false;

   static datetime lastNewsUpdate = 0;
   if(TimeCurrent() - lastNewsUpdate >= 1800)
     {
      g_NewsFilter.LoadNews();
      lastNewsUpdate = TimeCurrent();
     }

   static datetime lastCorrelationUpdate = 0;
   bool forceCorrelationUpdate = false;
   if(TimeCurrent() - lastCorrelationUpdate >= 14400)
      forceCorrelationUpdate = true;
   if(!forceCorrelationUpdate && g_lastAvgSpread > 0.0)
     {
      double avg = 0;
      for(int i=0;i<g_TotalAssets;i++)
         avg += (double)SymbolInfoInteger(g_Assets[i], SYMBOL_SPREAD);
      if(MathAbs(avg/g_TotalAssets - g_lastAvgSpread) / g_lastAvgSpread > 0.30)
         forceCorrelationUpdate = true;
     }
   if(!forceCorrelationUpdate && MathAbs(PositionsTotal() - g_lastPositionCount) > 2)
      forceCorrelationUpdate = true;
   if(forceCorrelationUpdate)
     {
      g_CorrelationEngine.UpdateCorrelationMatrix();
      lastCorrelationUpdate = TimeCurrent();
      g_lastAvgSpread = g_CorrelationEngine.GetLastAvgSpread();
      g_lastPositionCount = PositionsTotal();
     }

   if(TimeCurrent() - g_lastOnnxCheck >= 10)
     {
      g_lastOnnxCheck = TimeCurrent();
      CheckAndReloadOnnx();
     }

   static datetime lastDashUpdate = 0;
   if(TimeCurrent() - lastDashUpdate >= 2 && g_Dashboard != NULL && g_DashboardCreated)
     {
      lastDashUpdate = TimeCurrent();
      DashboardInfo info;
      info.balance        = AccountInfoDouble(ACCOUNT_BALANCE);
      info.equity         = AccountInfoDouble(ACCOUNT_EQUITY);
      info.dayStartEquity = g_GlobalRiskManager.GetDayStartEquity();
      info.totalOps       = PositionsTotal();
      info.drawdown       = (info.balance > 0) ? (1.0 - info.equity / info.balance) * 100.0 : 0.0;
      info.maxDailyDD     = InpMaxDailyLossPercent;
      ArrayResize(info.symbolMetrics, g_TotalAssets);
      double sumSpread=0, sumONNX=0, sumKNN=0, sumChop=0, sumVol=0;
      int totalOBs=0, totalFVGs=0, spreadCount=0, onnxCount=0, chopCount=0, volCount=0;
      bool anyNewsBlocked = false;

      for(int i=0; i<g_TotalAssets; i++)
        {
         if(!smcValid[i])
            continue;
         double sp = (double)SymbolInfoInteger(g_Assets[i], SYMBOL_SPREAD);
         sumSpread += sp;
         spreadCount++;
         sumONNX += g_LastProbONNX[i];
         sumKNN += g_LastProbKNN[i];
         onnxCount++;
         double chop = g_SmcAnalyzer[i].CalculateChoppinessIndex(14);
         if(chop != 50.0)
           {
            sumChop += chop;
            chopCount++;
           }

         double atrM15[1], atrH4[1];
         double vol = -1.0;
         if(g_HandleATR_M15[i]!=INVALID_HANDLE && g_HandleATR_H4[i]!=INVALID_HANDLE)
            if(CopyBuffer(g_HandleATR_M15[i],0,0,1,atrM15)==1 && CopyBuffer(g_HandleATR_H4[i],0,0,1,atrH4)==1 && atrH4[0]!=0.0)
               vol = atrM15[0] / atrH4[0];
         if(vol > 0)
           {
            sumVol += vol;
            volCount++;
           }
         totalOBs  += g_SmcAnalyzer[i].GetActiveOrderBlocks();
         totalFVGs += g_SmcAnalyzer[i].GetActiveFairValueGaps();

         double dummyFactor;
         if(g_NewsFilter.IsLockoutPeriod(g_Assets[i], dummyFactor))
            anyNewsBlocked = true;

         double dir = g_LastMacroDirection[i];
         double probONNX = g_LastProbONNX[i];
         double probKNN = g_LastProbKNN[i];
         bool zoneMit = g_LastMitigatedZone[i];
         double mitRatio = g_LastMitigationRatio[i];
         double relVol = 1.0;
         if(g_HandleATR_M1[i]!=INVALID_HANDLE && g_HandleATR_H4[i]!=INVALID_HANDLE)
           {
            double atr1v[1], atrH4v[1];
            if(CopyBuffer(g_HandleATR_M1[i],0,0,1,atr1v)==1 && CopyBuffer(g_HandleATR_H4[i],0,0,1,atrH4v)==1 && atrH4v[0]!=0.0)
               relVol = atr1v[0]/atrH4v[0];
           }
         double lastScore = g_SignalFilter[i].ProcessSignal((int)dir, probONNX, probKNN, zoneMit, mitRatio, relVol);
         double approvalPct = (InpApprovalThreshold > 0) ? (lastScore / InpApprovalThreshold) * 100.0 : 100.0;
         if(approvalPct > 200.0)
            approvalPct = 200.0;

         info.symbolMetrics[i].symbol = g_Assets[i];
         info.symbolMetrics[i].spread = (long)sp;
         info.symbolMetrics[i].newsBlocked = g_NewsFilter.IsLockoutPeriod(g_Assets[i], dummyFactor);
         info.symbolMetrics[i].iaSignal = (g_LastProbONNX[i] + (g_LastProbKNN[i]+1.0)/2.0)/2.0;
         info.symbolMetrics[i].choppiness = chop;
         info.symbolMetrics[i].volatility = (vol > 0) ? vol : 1.0;
         info.symbolMetrics[i].activeOBs = g_SmcAnalyzer[i].GetActiveOrderBlocks();
         info.symbolMetrics[i].activeFVGs = g_SmcAnalyzer[i].GetActiveFairValueGaps();
         info.symbolMetrics[i].approvalPct = approvalPct;
         info.symbolMetrics[i].direction = (int)dir;
        }

      info.avgSpread        = (spreadCount>0) ? sumSpread/spreadCount : 0;
      info.avgProbONNX      = (onnxCount>0)   ? sumONNX/onnxCount     : 0.5;
      info.avgProbKNN       = (onnxCount>0)   ? sumKNN/onnxCount      : 0.0;
      info.avgChoppiness    = (chopCount>0)   ? sumChop/chopCount     : 50.0;
      info.avgVolatility    = (volCount>0)    ? sumVol/volCount       : 1.0;
      info.totalActiveOBs   = totalOBs;
      info.totalActiveFVGs  = totalFVGs;
      info.newsBlocked      = anyNewsBlocked;

      bool anyModelLoaded = false;
      for(int j=0; j<g_TotalAssets; j++)
         if(statValid[j] && g_StatisticalFilter[j].IsModelLoaded())
           { anyModelLoaded = true; break; }
      info.onnxUpdated      = (TimeCurrent() - g_lastOnnxModTime < 3600) && anyModelLoaded;
      info.decouplingCount  = g_CorrelationEngine.GetDecouplingCount();
      g_Dashboard.Update(info);
      g_Dashboard.TryAutoExport(info);
     }

   if(InpAutoSaveMinutes > 0 && TimeCurrent() - g_lastAutoSave >= InpAutoSaveMinutes * 60)
     {
      g_lastAutoSave = TimeCurrent();
      SaveAllState();
      Print("Auto-save completed.");
     }

   static datetime lastKnnExport = 0;
   if(TimeCurrent() - lastKnnExport >= 21600)
     {
      lastKnnExport = TimeCurrent();
      string basePath = "Arion\\", finalCsv = basePath + "KNN.csv";
      if(FileIsExist(finalCsv))
         FileDelete(finalCsv);
      bool anyExported = false;
      for(int i=0; i<g_TotalAssets; i++)
        {
         if(!knnValid[i])
            continue;
         string tempFile = basePath + "temp_" + g_Assets[i] + ".csv";
         if(FileIsExist(tempFile))
            FileDelete(tempFile);
         if(g_KnnClassifier[i].ExportSamplesToCSV(tempFile))
           {
            int hCheck = FileOpen(tempFile, FILE_READ|FILE_TXT|FILE_ANSI);
            if(hCheck != INVALID_HANDLE)
              {
               string header = FileReadString(hCheck);
               string secondLine = FileReadString(hCheck);
               FileClose(hCheck);
               if(secondLine != "" && StringFind(secondLine, "slope,atr") == -1)
                  anyExported = true;
               else
                  FileDelete(tempFile);
              }
           }
        }
      if(anyExported)
        {
         int hFinal = FileOpen(finalCsv, FILE_WRITE|FILE_TXT|FILE_ANSI);
         if(hFinal != INVALID_HANDLE)
           {
            bool firstFile = true;
            for(int i=0; i<g_TotalAssets; i++)
              {
               string tempFile = basePath + "temp_" + g_Assets[i] + ".csv";
               if(FileIsExist(tempFile))
                 {
                  int hTemp = FileOpen(tempFile, FILE_READ|FILE_TXT|FILE_ANSI);
                  if(hTemp != INVALID_HANDLE)
                    {
                     while(!FileIsEnding(hTemp))
                       {
                        string line = FileReadString(hTemp);
                        if(!firstFile && StringFind(line, "slope,atr") == 0)
                           continue;
                        if(StringFind(line, "#") == 0)
                           continue;
                        FileWrite(hFinal, line);
                       }
                     FileClose(hTemp);
                     FileDelete(tempFile);
                     firstFile = false;
                    }
                 }
              }
            FileClose(hFinal);
            int hFinalCheck = FileOpen(finalCsv, FILE_READ|FILE_TXT|FILE_ANSI);
            if(hFinalCheck != INVALID_HANDLE)
              {
               string header = FileReadString(hFinalCheck);
               string secondLine = FileReadString(hFinalCheck);
               FileClose(hFinalCheck);
               if(secondLine != "" && StringFind(secondLine, "slope,atr") == -1)
                  ExecutePythonTrainer();
               else
                  Print("KNN.csv vacio, no se lanzo el entrenamiento.");
              }
           }
        }
      else
         Print("No se exportaron muestras de ningun activo. Autoentrenamiento omitido.");
     }

   static bool onnxVerified = false;
   if(!onnxVerified)
     {
      if(g_StatisticalFilter[0] != NULL &&
         g_StatisticalFilter[0].IsModelLoaded() &&
         g_StatisticalFilter[0].GetOutputSize() == 5)
        {
         onnxVerified = true;
         Print("ONNX model verified (5 classes). Trading enabled.");
        }
      else
         return;
     }

   // ---- BUCLE PRINCIPAL DE TRADING ----
   for(int i=0; i<g_TotalAssets; i++)
     {
      if(!InpEnableAll)
         break;
      if(!riskValid[i])
         continue;
      string sym = g_Assets[i];
      if(!VerifySymbolHistory(sym, i, g_TFMacro, 50) ||
         !VerifySymbolHistory(sym, i, g_TFZone, 100) ||
         !VerifySymbolHistory(sym, i, g_TFTrigger, 200))
         continue;

      long spread = SymbolInfoInteger(sym, SYMBOL_SPREAD);
      if(g_NewsFilter != NULL)
        {
         double sf;
         if(g_NewsFilter.IsLockoutPeriod(sym, sf) && spread > InpMaxSpreadPoints * sf)
            continue;
        }
      if(!g_SignalFilter[i].PassHardFilters(spread, InpMaxTradesPerSymbol))
         continue;

      if(TimeCurrent() - g_LastBECheck[i] >= 2)
        {
         g_Executor[i].ManageBreakeven(1.0, 5.0);
         g_LastBECheck[i] = TimeCurrent();
        }
      if(InpActivateTrailing)
         g_Executor[i].ManageTrailingStop(InpTrailStartRatio, InpTrailDistancePips, InpTrailStepPips, InpTrailATRMultiplier);

      bool newMacro   = IsNewBarFast(sym, g_TFMacro,   g_LastBarTimeMacro[i]);
      bool newZona    = IsNewBarFast(sym, g_TFZone,    g_LastBarTimeZona[i]);
      bool newGatillo = IsNewBarFast(sym, g_TFTrigger, g_LastBarTimeGatillo[i]);
      if(newMacro || newZona)
         g_SmcAnalyzer[i].UpdateStructure(newMacro, newZona);
      if(newGatillo)
         g_SignalFilter[i].OnNewBar();

      // --- ENTRENAMIENTO KNN CON ETIQUETAS REALES (NUEVA LÓGICA) ---
      if(newZona && knnValid[i])
        {
         double sl, at, mo, fl, ad, rs, dv, sd, sm, rl, nv, vr;
         if(CalculateKNNFeatures(sym, i, sl, at, mo, fl, ad, rs, dv, sd, sm, rl, nv, vr))
           {
            double features[12];
            features[0]=sl; features[1]=at; features[2]=mo; features[3]=fl;
            features[4]=ad; features[5]=rs; features[6]=dv; features[7]=sd;
            features[8]=sm; features[9]=rl; features[10]=nv; features[11]=vr;

            // Obtener precio de cierre de la vela M15 recién formada
            double close = iClose(sym, g_TFZone, 0);
            g_LabelGen[i].OnNewBar(close, features);

            // Consumir muestras completadas y añadirlas al KNN
            while(g_LabelGen[i].IsReady())
              {
               g_KnnClassifier[i].AddSampleFromLabelGenerator(g_LabelGen[i]);
               g_LabelGen[i].ConsumeOldest();
              }

            // Persistencia automática del KNN
            if(g_KnnClassifier[i].IsAutoSavePending())
              {
               g_KnnClassifier[i].SaveState("Arion\\KNN\\" + g_Assets[i] + ".bin");
               g_KnnClassifier[i].ResetAutoSaveFlag();
              }
           }
        }

      // --- LÓGICA DE SEÑAL (sin cambios) ---
      if(!newGatillo || !allowSignals)
         continue;
      double dir = g_SmcAnalyzer[i].GetMacroDirection();
      if(dir == 0.0)
         continue;
      double ask = SymbolInfoDouble(sym, SYMBOL_ASK), bid = SymbolInfoDouble(sym, SYMBOL_BID);
      double price = (dir > 0) ? ask : bid, point = SymbolInfoDouble(sym, SYMBOL_POINT);

      bool recalc = false;
      if((datetime)SeriesInfoInteger(sym, g_TFTrigger, SERIES_LASTBAR_DATE) > g_LastCalcBarTime[i])
         recalc = true;
      else
         if(MathAbs(price - g_LastCalcPrice[i]) >= InpMinPipsDisplacement * point)
            recalc = true;
         else
            if(MathAbs(dir - g_LastMacroDirection[i]) > 1e-10)
               recalc = true;

      double probONNX = g_LastProbONNX[i], probKNN = g_LastProbKNN[i];
      bool zoneMit = g_LastMitigatedZone[i];
      double mitRatio = g_LastMitigationRatio[i], relVol = 1.0;

      if(recalc && statValid[i])
        {
         zoneMit = g_SmcAnalyzer[i].IsOBMitigated(price, dir>0) || g_SmcAnalyzer[i].IsFVGMitigated(price, dir>0);
         mitRatio = g_SmcAnalyzer[i].GetOBMitigationRatio(price, dir>0);
         double atr1v[1], atrH4v[1];
         if(g_HandleATR_M1[i]!=INVALID_HANDLE && g_HandleATR_H4[i]!=INVALID_HANDLE)
            if(CopyBuffer(g_HandleATR_M1[i],0,0,1,atr1v)==1 && CopyBuffer(g_HandleATR_H4[i],0,0,1,atrH4v)==1 && atrH4v[0]!=0.0)
               relVol = atr1v[0]/atrH4v[0];

         double sl, at, mo, fl, ad, rs, dv, sd, sm, rl, nv, vr;
         bool featuresOk = CalculateKNNFeatures(sym, i, sl, at, mo, fl, ad, rs, dv, sd, sm, rl, nv, vr);
         if(featuresOk)
           {
            double probBuy = 0.5, probSell = 0.5;
            if(g_StatisticalFilter[i].IsModelLoaded())
              {
               g_StatisticalFilter[i].CalculateVolumeZScore();
               float inputs[12] = {(float)sl, (float)at, (float)mo, (float)fl, (float)ad, (float)rs,
                                   (float)dv, (float)sd, (float)sm, (float)rl, (float)nv, (float)vr
                                  };
               if(!g_StatisticalFilter[i].ExecuteXGBoostPrediction(inputs, probBuy, probSell))
                 { probBuy = 0.5; probSell = 0.5; }
              }
            probONNX = (dir > 0) ? probBuy : probSell;
            probKNN  = g_KnnClassifier[i].CalculateKNNProbability(sl, at, mo, fl, ad, rs, dv, sd, sm, rl, nv, vr, 15);
           }
         g_LastCalcBarTime[i]     = (datetime)SeriesInfoInteger(sym, g_TFTrigger, SERIES_LASTBAR_DATE);
         g_LastCalcPrice[i]       = price;
         g_LastProbONNX[i]        = probONNX;
         g_LastProbKNN[i]         = probKNN;
         g_LastMitigatedZone[i]   = zoneMit;
         g_LastMitigationRatio[i] = mitRatio;
         g_LastMacroDirection[i]  = dir;
        }

      double score = g_SignalFilter[i].ProcessSignal((int)dir, probONNX, probKNN, zoneMit, mitRatio, relVol);
      if(score < InpApprovalThreshold)
         continue;

      double slPoints = 200.0;
        { double atr1v[1]; if(g_HandleATR_M1[i]!=INVALID_HANDLE && CopyBuffer(g_HandleATR_M1[i],0,0,1,atr1v)==1 && atr1v[0]>0) slPoints = atr1v[0] * InpATRMultiplierSL / point; }

      int stopsLevel = (int)SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
      if(stopsLevel > 0 && slPoints < stopsLevel)
         slPoints = stopsLevel * 1.2;

      double tpPoints = 0;
      double tpLevel = g_SmcAnalyzer[i].FindOppositeLiquidity(price, dir > 0);
      bool useLiquidityTP = false;
      if(tpLevel > 0.0)
        {
         double tpDist = (dir > 0) ? (tpLevel - price) : (price - tpLevel);
         double liqTP = tpDist / point;
         if(liqTP / slPoints >= 2.0)
           {
            tpPoints = liqTP;
            useLiquidityTP = true;
           }
        }
      if(!useLiquidityTP)
         tpPoints = slPoints * InpRRRatio;

      double lot = g_RiskManager[i].CalculateLots(InpRiskPercentage, slPoints);
      if(lot <= 0.0)
         continue;

      if(InpMaxExposureCurrency > 0.0)
        {
         string baseCurrency = SymbolInfoString(sym, SYMBOL_CURRENCY_BASE);
         string quoteCurrency = SymbolInfoString(sym, SYMBOL_CURRENCY_PROFIT);
         double baseExposure = GetCurrencyExposure(baseCurrency);
         double quoteExposure = GetCurrencyExposure(quoteCurrency);
         double point2 = SymbolInfoDouble(sym, SYMBOL_POINT);
         double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
         double newRisk = slPoints * tickValue * lot / point2;
         
         if(baseExposure + newRisk > InpMaxExposureCurrency || quoteExposure + newRisk > InpMaxExposureCurrency)
           {
            Print("Currency exposure limit reached for ", baseCurrency, " or ", quoteCurrency);
            continue;
           }
        }

      ENUM_ORDER_TYPE type = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(g_Executor[i].SendMarketOrder(type, lot, slPoints, tpPoints, "Arion_"+sym))
         g_SignalFilter[i].OnPositionOpened();
     }
  }

//+------------------------------------------------------------------+
//| OnTradeTransaction                                               |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
  {
   for(int i=0; i<g_TotalAssets; i++)
      if(CheckPointer(g_Executor[i]) == POINTER_DYNAMIC)
         g_Executor[i].ProcessTransaction(trans, request, result);

   if(trans.type == TRADE_TRANSACTION_ORDER_ADD ||
      trans.type == TRADE_TRANSACTION_ORDER_UPDATE ||
      trans.type == TRADE_TRANSACTION_ORDER_DELETE)
     {
      PrintFormat("Transaction: %s | Order: %d | %s | Retcode: %d | Price: %.5f | Vol: %.2f",
                  EnumToString(trans.type), trans.order, trans.symbol, result.retcode, result.price, result.volume);
      if(result.retcode == TRADE_RETCODE_DONE)
        {
         string typeStr = (trans.type == TRADE_TRANSACTION_ORDER_ADD) ? "OPEN" :
                          (trans.type == TRADE_TRANSACTION_ORDER_DELETE) ? "CLOSE" : "UPDATE";
         Logger::LogTrade(trans.symbol, typeStr, trans.order, result.price, result.volume, request.sl, request.tp);
        }
     }
   if(result.retcode != TRADE_RETCODE_DONE && result.retcode != 0)
     {
      Print("Execution error: ", result.retcode, " - ", result.comment);
      Logger::CriticalAlert("Execution error: " + result.comment);
     }
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD && result.retcode == TRADE_RETCODE_DONE)
     {
      if(HistoryDealSelect(trans.deal))
        {
         double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
         double closePrice = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
         long   ticket     = HistoryDealGetInteger(trans.deal, DEAL_ORDER);
         int n = ArraySize(g_Trades);
         ArrayResize(g_Trades, n+1);
         g_Trades[n].profit    = profit;
         g_Trades[n].balance   = AccountInfoDouble(ACCOUNT_BALANCE);
         g_Trades[n].closeTime = TimeCurrent();

         Logger::LogClose(trans.symbol, ticket, closePrice, profit);

         for(int i=0; i<g_TotalAssets; i++)
           {
            if(g_Assets[i] == trans.symbol && CheckPointer(g_SignalFilter[i]) == POINTER_DYNAMIC)
               g_SignalFilter[i].OnPositionClosed(profit < 0);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| OnChartEvent                                                     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(g_Dashboard != NULL)
      g_Dashboard.OnChartEvent(id, lparam, dparam, sparam);
  }

//+------------------------------------------------------------------+
//| OnTester...                                                      |
//+------------------------------------------------------------------+
int OnTesterInit()
  {
   ParameterSetRange("InpWeightONNX",    false, InpWeightONNX,    20.0, 5.0, 40.0);
   ParameterSetRange("InpWeightKNN",     false, InpWeightKNN,     15.0, 5.0, 35.0);
   ParameterSetRange("InpWeightSMC",     false, InpWeightSMC,     15.0, 5.0, 35.0);
   ParameterSetRange("InpWeightContext", false, InpWeightContext,  5.0, 5.0, 25.0);
   return 0;
  }

void OnTesterDeinit() {}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double OnTester()
  {
   double sharpe = Metrics::CalculateSharpeRatio(g_Trades),
          pf     = Metrics::CalculateProfitFactor(g_Trades),
          dd     = Metrics::CalculateMaxDrawdown(g_Trades);
   double score = sharpe * pf * (1.0 - dd);
   int h = FileOpen("Arion\\WF_Report.csv", FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h != INVALID_HANDLE)
     {
      FileSeek(h, 0, SEEK_END);
      if(FileTell(h)==0)
         FileWrite(h, "Step,Sharpe,ProfitFactor,MaxDrawdown,Score,PesoONNX,PesoKNN,PesoSMC,PesoContexto,lambda");
      FileWrite(h, g_step++, sharpe, pf, dd, score, InpWeightONNX, InpWeightKNN, InpWeightSMC, InpWeightContext, 0.0002);
      FileClose(h);
     }
   return score;
  }
//+------------------------------------------------------------------+