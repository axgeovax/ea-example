//+------------------------------------------------------------------+
//|                                                       Arion.mq5 |
//|                        Arion - EA Multidivisa                    |
//|    ULL optimizado, Persistencia, Gestión Riesgo Global,          |
//|    Noticias, Logging, Dashboard, Métricas, Validación de Inputs  |
//|    Walk‑Forward Integrado, Recarga ONNX en Caliente,             |
//|    Trailing Stop Individual, Créditos Diarios,                  |
//|    Modelo ONNX incrustado (12D), KNN 12D (ADX, RSI)            |
//|                        Autor: Alexy Hernández                    |
//|                        Versión: 1.0                              |
//|        Copyright (c) 2025 Alexy Hernández. Todos los derechos    |
//|        reservados.                                               |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernández. Todos los derechos reservados."
#property link      "https://github.com/axgeovax"
#property version   "1.0"
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

//+------------------------------------------------------------------+
//| Inputs                                                            |
//+------------------------------------------------------------------+
input bool     InpEnableAll              = true;      // Habilitar operativa general
input double   InpRiskPercentage         = 1.0;       // Riesgo porcentual por operación
input double   InpATRMultiplierSL        = 1.5;       // Multiplicador del ATR para Stop Loss
input double   InpRRRatio                = 3.0;       // Ratio Riesgo/Beneficio mínimo
input int      InpMaxSpreadPoints        = 50;        // Spread máximo permitido en puntos
input int      InpMaxTradesPerSymbol     = 3;         // Máximo de operaciones simultáneas por símbolo
input int      InpTimerMilliseconds      = 100;       // Intervalo del timer (milisegundos)
input double   InpWeightONNX             = 35.0;      // Peso del modelo ONNX en el score
input double   InpWeightKNN              = 25.0;      // Peso del clasificador KNN
input double   InpWeightSMC              = 25.0;      // Peso del análisis SMC
input double   InpWeightContext          = 15.0;      // Peso del contexto de volatilidad
input double   InpApprovalThreshold      = 75.0;      // Puntuación mínima para abrir orden
input int      InpMinPipsDisplacement    = 2;         // Desplazamiento mínimo en pips para recalcular señal
input double   InpMaxDailyLossPercent    = 5.0;       // Pérdida diaria máxima (% equity)
input int      InpMaxGlobalTrades        = 15;        // Máximo global de posiciones abiertas
input double   InpAccountTrailingStop    = 10.0;      // Trailing stop de cuenta (% desde máximo equity)
input bool     InpCloseAllOnStop         = false;     // Cerrar todas las posiciones al tocar el trailing stop de cuenta
input string   InpNewsCSVPath            = "Arion\\News.csv"; // Ruta del CSV de noticias
input string   InpNewsApiUrl             = "";        // URL de la API de noticias (opcional)
input int      InpMinNewsImpact          = 3;         // Impacto mínimo de noticias (1=bajo, 2=medio, 3=alto)
input int      InpMinutesBeforeNews      = 15;        // Minutos de bloqueo antes de la noticia
input int      InpMinutesAfterNews       = 15;        // Minutos de bloqueo después de la noticia
input double   InpNewsSpreadFactor       = 0.5;       // Factor de ampliación del spread durante noticias
input string   InpLogCSVFile             = "Arion\\Log.csv"; // Archivo de log
input bool     InpEnablePush             = false;     // Activar notificaciones Push
input bool     InpEnableEmail            = false;     // Activar notificaciones por Email
input string   InpDestEmail              = "";        // Dirección de correo para alertas
input string   InpEmailSubject           = "Arion";   // Asunto del correo de alerta
input int      InpAsyncOrderTimeout      = 30;        // Timeout de órdenes asíncronas (segundos)
input int      InpMondayCooldownMinutes  = 30;        // Minutos de enfriamiento al inicio del lunes
input int      InpMaxDailyCredits        = 3;         // Créditos diarios para nuevas entradas
input bool     InpActivateTrailing       = true;      // Activar trailing stop individual
input double   InpTrailStartRatio        = 1.5;       // Ratio de ganancia para iniciar trailing
input double   InpTrailDistancePips      = 50.0;      // Distancia del trailing stop (pips)
input double   InpTrailStepPips          = 5.0;       // Paso mínimo de ajuste del trailing (pips)
input string   InpPythonPath             = "python.exe"; // Ruta o comando del ejecutable de Python
input int      InpAutoSaveMinutes        = 30;        // Intervalo de auto-guardado (minutos)

//+------------------------------------------------------------------+
//| Data Guard                                                        |
//+------------------------------------------------------------------+
bool g_HistoryOK[10];
datetime g_LastHistoryCheck[10];

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool VerifySymbolHistory(string symbol, int idx, ENUM_TIMEFRAMES tf, int min_bars)
  {
   if(g_LastHistoryCheck[idx] != 0 && TimeCurrent() - g_LastHistoryCheck[idx] < 300)
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
                     "USDCAD","USDJPY","XAUUSD","XAGUSD","AUDJPY"
                    };
int g_TotalAssets = 10;
ENUM_TIMEFRAMES g_TFMacro = PERIOD_H4, g_TFZone = PERIOD_M15, g_TFTrigger = PERIOD_M1;

RiskManager*         g_RiskManager[];
SmartMoney*          g_SmcAnalyzer[];
Executor*            g_Executor[];
OnnxPredictor*       g_StatisticalFilter[];
KnnClassifier*       g_KnnClassifier[];
SignalFilter*        g_SignalFilter[];
CorrelationEngine*   g_CorrelationEngine;
GlobalRiskManager*   g_GlobalRiskManager;
NewsFilter*          g_NewsFilter;
Dashboard*           g_Dashboard;
bool                 g_DashboardCreated = false;

datetime g_LastBarTimeMacro[], g_LastBarTimeZona[], g_LastBarTimeGatillo[];
int g_HandleATR_M1[], g_HandleATR_M15[], g_HandleATR_H4[];

datetime g_LastCalcBarTime[10];
double   g_LastCalcPrice[10];
double   g_LastProbONNX[10];
double   g_LastProbKNN[10];
bool     g_LastMitigatedZone[10];
double   g_LastMitigationRatio[10];
double   g_LastMacroDirection[10];
datetime g_LastBECheck[10];

TradeResult g_Trades[];
int g_step = 0;

datetime g_lastOnnxCheck = 0;
datetime g_lastOnnxModTime = 0;
double   g_lastAvgSpread = 0.0;
int      g_lastPositionCount = 0;
datetime g_lastAutoSave = 0;

//+------------------------------------------------------------------+
//|                                                                  |
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
//|                                                                  |
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
               g_StatisticalFilter[i].LoadONNXModel(onnxPath);
         Print("ONNX model hot‑reloaded (modTime=", modTime, ")");
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool ValidateInputs()
  {
   double sumWeights = InpWeightONNX + InpWeightKNN + InpWeightSMC + InpWeightContext;
   if(MathAbs(sumWeights - 100.0) > 1.0)
     {
      Print("Error: Filter weights must sum 100%.");
      return false;
     }
   if(InpRiskPercentage <= 0.0 || InpRiskPercentage > 100.0)
     {
      Print("Error: RiskPercentage must be between 0.01 and 100.");
      return false;
     }
   if(InpATRMultiplierSL <= 0.0)
     {
      Print("Error: ATRMultiplierSL must be positive.");
      return false;
     }
   if(InpRRRatio <= 0.0)
     {
      Print("Error: RR must be positive.");
      return false;
     }
   if(InpMaxSpreadPoints < 0)
     {
      Print("Error: MaxSpreadPoints cannot be negative.");
      return false;
     }
   if(InpMaxTradesPerSymbol < 0)
     {
      Print("Error: MaxTradesPerSymbol cannot be negative.");
      return false;
     }
   if(InpMinPipsDisplacement < 0)
     {
      Print("Error: MinPipsDisplacement cannot be negative.");
      return false;
     }
   if(InpMaxDailyLossPercent < 0.0 || InpMaxDailyLossPercent > 100.0)
     {
      Print("Error: MaxDailyLossPercent must be between 0 and 100.");
      return false;
     }
   if(InpMaxGlobalTrades < 0)
     {
      Print("Error: MaxGlobalTrades cannot be negative.");
      return false;
     }
   if(InpAccountTrailingStop < 0.0 || InpAccountTrailingStop > 100.0)
     {
      Print("Error: AccountTrailingStop must be between 0 and 100.");
      return false;
     }
   if(InpAsyncOrderTimeout <= 0)
     {
      Print("Error: AsyncOrderTimeout must be positive.");
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SaveAllState()
  {
   string base = "Arion\\";
   for(int i=0; i<g_TotalAssets; i++)
     {
      if(CheckPointer(g_SmcAnalyzer[i]) == POINTER_DYNAMIC)
         g_SmcAnalyzer[i].SaveState(base + "SMC_" + g_Assets[i] + ".bin");
      if(CheckPointer(g_KnnClassifier[i]) == POINTER_DYNAMIC)
         g_KnnClassifier[i].SaveState(base + "KNN_" + g_Assets[i] + ".bin");
     }
   g_GlobalRiskManager.SaveState(base + "RiskManager.bin");
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

   ArrayResize(g_RiskManager, g_TotalAssets);
   ArrayResize(g_SmcAnalyzer, g_TotalAssets);
   ArrayResize(g_Executor, g_TotalAssets);
   ArrayResize(g_StatisticalFilter, g_TotalAssets);
   ArrayResize(g_KnnClassifier, g_TotalAssets);
   ArrayResize(g_SignalFilter, g_TotalAssets);
   ArrayResize(g_LastBarTimeMacro, g_TotalAssets);
   ArrayResize(g_LastBarTimeZona, g_TotalAssets);
   ArrayResize(g_LastBarTimeGatillo, g_TotalAssets);
   ArrayResize(g_HandleATR_M1, g_TotalAssets);
   ArrayResize(g_HandleATR_M15, g_TotalAssets);
   ArrayResize(g_HandleATR_H4, g_TotalAssets);

   g_CorrelationEngine = new CorrelationEngine();
   g_CorrelationEngine.Initialize(g_Assets, g_TotalAssets);

   g_GlobalRiskManager = new GlobalRiskManager();
   g_GlobalRiskManager.Configure(InpMaxDailyLossPercent, InpMaxGlobalTrades, InpAccountTrailingStop, InpCloseAllOnStop);
   g_GlobalRiskManager.SetMagicRange(202400, g_TotalAssets);
   g_GlobalRiskManager.SetMaxDailyCredits(InpMaxDailyCredits);
   g_GlobalRiskManager.LoadState("Arion\\RiskManager.bin");

   g_NewsFilter = new NewsFilter();
   g_NewsFilter.Configure(InpNewsCSVPath, InpNewsApiUrl, InpMinNewsImpact, InpMinutesBeforeNews, InpMinutesAfterNews, InpNewsSpreadFactor);
   g_NewsFilter.LoadNews();

   Logger::Initialize(InpLogCSVFile, InpEnablePush, InpEnableEmail, InpDestEmail, InpEmailSubject);

   CreateTrainScriptIfMissing();
   EnsureInitialOnnxModel();

   g_Dashboard = new Dashboard();
   g_DashboardCreated = false;

   g_lastOnnxCheck = 0;
   g_lastOnnxModTime = 0;
   g_lastAvgSpread = 0.0;
   g_lastPositionCount = 0;
   g_lastAutoSave = TimeCurrent();

   bool onnxValid = false;
   string onnxPath = "Arion\\ArionIntelligence.onnx";
   if(FileIsExist(onnxPath))
     {
      ulong onnxSize = FileGetInteger(onnxPath, FILE_SIZE, false);
      if(onnxSize > 100)
         onnxValid = true;
     }
   if(onnxValid)
      g_lastOnnxModTime = (datetime)FileGetInteger(onnxPath, FILE_MODIFY_DATE, false);

   for(int i=0; i<g_TotalAssets; i++)
     {
      string sym = g_Assets[i];
      if(!SymbolSelect(sym, true))
        {
         Print("Symbol ", sym, " not available");
         continue;
        }
      g_RiskManager[i]       = new RiskManager(sym, g_CorrelationEngine);
      g_SmcAnalyzer[i]       = new SmartMoney(sym);
      g_Executor[i]          = new Executor(sym, 202400 + i);
      g_StatisticalFilter[i] = new OnnxPredictor(sym);
      g_KnnClassifier[i]     = new KnnClassifier(500, 0.002);
      g_SignalFilter[i]      = new SignalFilter(sym);

      g_Executor[i].SetAsyncTimeout(InpAsyncOrderTimeout);
      g_SmcAnalyzer[i].Initialize();
      g_Executor[i].Initialize();
      if(onnxValid)
         g_StatisticalFilter[i].Initialize(20, 2.0, true);
      else
         g_StatisticalFilter[i].Initialize(20, 2.0, false);

      g_SmcAnalyzer[i].LoadState("Arion\\SMC_" + sym + ".bin");
      g_KnnClassifier[i].LoadState("Arion\\KNN_" + sym + ".bin");

      g_LastBarTimeMacro[i] = g_LastBarTimeZona[i] = g_LastBarTimeGatillo[i] = 0;
      g_HandleATR_M1[i]  = iATR(sym, g_TFTrigger, 14);
      g_HandleATR_M15[i] = iATR(sym, g_TFZone, 14);
      g_HandleATR_H4[i]  = iATR(sym, g_TFMacro, 14);

      g_LastCalcBarTime[i]     = 0;
      g_LastCalcPrice[i]       = 0.0;
      g_LastProbONNX[i]        = 0.5;
      g_LastProbKNN[i]         = 0.0;
      g_LastMitigatedZone[i]   = false;
      g_LastMitigationRatio[i] = 0.0;
      g_LastMacroDirection[i]  = 0.0;
      g_LastHistoryCheck[i]    = 0;
      g_HistoryOK[i]           = false;
      g_LastBECheck[i]         = 0;
     }

   EventSetMillisecondTimer(InpTimerMilliseconds);
   Print("Arion v1.0 initialized (12D ONNX + Fractal SMC)");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   SaveAllState();
   Logger::Close();

   for(int i=0; i<g_TotalAssets; i++)
     {
      if(CheckPointer(g_SmcAnalyzer[i]) == POINTER_DYNAMIC)
         g_SmcAnalyzer[i].SaveState("Arion\\SMC_" + g_Assets[i] + ".bin");
      if(CheckPointer(g_KnnClassifier[i]) == POINTER_DYNAMIC)
         g_KnnClassifier[i].SaveState("Arion\\KNN_" + g_Assets[i] + ".bin");
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
      g_Dashboard.Initialize();
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
//| OnTimer                                                           |
//+------------------------------------------------------------------+
void OnTimer()
  {
   if(!g_DashboardCreated)
     {
      g_Dashboard.Initialize();
      ChartRedraw(0);
      g_DashboardCreated = true;
     }

   for(int i=0; i<g_TotalAssets; i++)
     {
      if(CheckPointer(g_RiskManager[i]) == POINTER_DYNAMIC)
         g_RiskManager[i].UpdateProperties();
      if(CheckPointer(g_Executor[i]) == POINTER_DYNAMIC)
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

// Correlación adaptativa
   static datetime lastCorrelationUpdate = 0;
   bool forceCorrelationUpdate = false;
   if(TimeCurrent() - lastCorrelationUpdate >= 14400)
      forceCorrelationUpdate = true;
   if(!forceCorrelationUpdate && g_lastAvgSpread > 0.0)
     {
      double currentAvgSpread = 0.0;
      for(int i=0; i<g_TotalAssets; i++)
         currentAvgSpread += (double)SymbolInfoInteger(g_Assets[i], SYMBOL_SPREAD);
      currentAvgSpread /= g_TotalAssets;
      if(MathAbs(currentAvgSpread - g_lastAvgSpread) / g_lastAvgSpread > 0.30)
         forceCorrelationUpdate = true;
     }
   if(!forceCorrelationUpdate)
     {
      int currentPositions = PositionsTotal();
      if(MathAbs(currentPositions - g_lastPositionCount) > 2)
         forceCorrelationUpdate = true;
     }
   if(forceCorrelationUpdate)
     {
      g_CorrelationEngine.UpdateCorrelationMatrix();
      lastCorrelationUpdate = TimeCurrent();
      g_lastAvgSpread = g_CorrelationEngine.GetLastAvgSpread();
      g_lastPositionCount = PositionsTotal();
     }

// Recarga ONNX cada 10s
   if(TimeCurrent() - g_lastOnnxCheck >= 10)
     {
      g_lastOnnxCheck = TimeCurrent();
      CheckAndReloadOnnx();
     }

// Dashboard global cada 2s
   static datetime lastDashUpdate = 0;
   if(TimeCurrent() - lastDashUpdate >= 2 && g_Dashboard != NULL && g_DashboardCreated)
     {
      lastDashUpdate = TimeCurrent();
      DashboardInfo info;
      info.balance = AccountInfoDouble(ACCOUNT_BALANCE);
      info.equity = AccountInfoDouble(ACCOUNT_EQUITY);
      info.dayStartEquity = g_GlobalRiskManager.GetDayStartEquity();
      info.totalOps = PositionsTotal();
      info.drawdown = (info.balance > 0) ? (1.0 - info.equity / info.balance) * 100.0 : 0.0;
      info.maxDailyDD = InpMaxDailyLossPercent;
      double sumSpread = 0;
      int spreadCount = 0;
      double sumONNX = 0, sumKNN = 0;
      double sumChop = 0, sumVol = 0;
      int totalOBs = 0, totalFVGs = 0;
      int onnxCount = 0, chopCount = 0, volCount = 0;
      bool anyNewsBlocked = false;
      for(int i=0; i<g_TotalAssets; i++)
        {
         if(CheckPointer(g_SmcAnalyzer[i]) == POINTER_DYNAMIC)
           {
            double spread = (double)SymbolInfoInteger(g_Assets[i], SYMBOL_SPREAD);
            sumSpread += spread;
            spreadCount++;
            sumONNX += g_LastProbONNX[i];
            sumKNN += g_LastProbKNN[i];
            onnxCount++;
            double chop = g_SmcAnalyzer[i].CalculateChoppinessIndex(14);
            sumChop += chop;
            chopCount++;
            double atr1[1], atrH4[1];
            double vol = 1.0;
            if(g_HandleATR_M1[i] != INVALID_HANDLE && g_HandleATR_H4[i] != INVALID_HANDLE)
               if(CopyBuffer(g_HandleATR_M1[i],0,0,1,atr1)==1 && CopyBuffer(g_HandleATR_H4[i],0,0,1,atrH4)==1 && atrH4[0]!=0.0)
                  vol = atr1[0]/atrH4[0];
            sumVol += vol;
            volCount++;
            totalOBs  += g_SmcAnalyzer[i].GetActiveOrderBlocks();
            totalFVGs += g_SmcAnalyzer[i].GetActiveFairValueGaps();
            double dummyFactor;
            if(g_NewsFilter.IsLockoutPeriod(g_Assets[i], dummyFactor))
               anyNewsBlocked = true;
           }
        }
      info.avgSpread      = (spreadCount > 0) ? sumSpread / spreadCount : 0;
      info.avgProbONNX    = (onnxCount > 0)   ? sumONNX   / onnxCount   : 0.5;
      info.avgProbKNN     = (onnxCount > 0)   ? sumKNN    / onnxCount   : 0.0;
      info.avgChoppiness  = (chopCount > 0)   ? sumChop   / chopCount   : 0.0;
      info.avgVolatility  = (volCount > 0)    ? sumVol    / volCount    : 1.0;
      info.totalActiveOBs = totalOBs;
      info.totalActiveFVGs = totalFVGs;
      info.newsBlocked    = anyNewsBlocked;
      info.onnxUpdated    = (TimeCurrent() - g_lastOnnxModTime < 3600) && g_StatisticalFilter[0].IsModelLoaded();
      info.decouplingCount = g_CorrelationEngine.GetDecouplingCount();
      g_Dashboard.Update(info);
     }

// Auto‑guardado
   if(InpAutoSaveMinutes > 0 && TimeCurrent() - g_lastAutoSave >= InpAutoSaveMinutes * 60)
     {
      g_lastAutoSave = TimeCurrent();
      SaveAllState();
      Print("📀 Auto‑save completed.");
     }

// Exportación KNN y auto‑entrenamiento
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
         if(CheckPointer(g_KnnClassifier[i]) == POINTER_DYNAMIC)
           {
            string tempFile = basePath + "temp_" + g_Assets[i] + ".csv";
            if(g_KnnClassifier[i].ExportSamplesToCSV(tempFile))
               anyExported = true;
           }
        }
      if(anyExported)
        {
         int hFinal = FileOpen(finalCsv, FILE_WRITE | FILE_TXT | FILE_ANSI);
         if(hFinal != INVALID_HANDLE)
           {
            bool firstFile = true;
            for(int i=0; i<g_TotalAssets; i++)
              {
               string tempFile = basePath + "temp_" + g_Assets[i] + ".csv";
               if(FileIsExist(tempFile))
                 {
                  int hTemp = FileOpen(tempFile, FILE_READ | FILE_TXT | FILE_ANSI);
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
            ExecutePythonTrainer();
           }
        }
     }

// Evaluación por símbolo
   for(int i=0; i<g_TotalAssets; i++)
     {
      if(!InpEnableAll)
         break;
      if(CheckPointer(g_RiskManager[i]) == POINTER_INVALID)
         continue;
      string sym = g_Assets[i];
      if(!VerifySymbolHistory(sym, i, g_TFMacro, 50) || !VerifySymbolHistory(sym, i, g_TFZone, 100) || !VerifySymbolHistory(sym, i, g_TFTrigger, 200))
         continue;
      long spread = SymbolInfoInteger(sym, SYMBOL_SPREAD);
      if(CheckPointer(g_NewsFilter) == POINTER_DYNAMIC)
        {
         double spreadFactor = 1.0;
         if(g_NewsFilter.IsLockoutPeriod(sym, spreadFactor) && spread > InpMaxSpreadPoints * spreadFactor)
           { Print("Symbol ", sym, " blocked by news"); continue; }
        }
      if(!g_SignalFilter[i].PassHardFilters(spread, InpMaxTradesPerSymbol))
         continue;
      if(TimeCurrent() - g_LastBECheck[i] >= 2)
        {
         g_Executor[i].ManageBreakeven(1.0, 5.0);
         g_LastBECheck[i] = TimeCurrent();
        }
      if(InpActivateTrailing)
         g_Executor[i].ManageTrailingStop(InpTrailStartRatio, InpTrailDistancePips, InpTrailStepPips);

      bool newMacro   = IsNewBarFast(sym, g_TFMacro,   g_LastBarTimeMacro[i]);
      bool newZona    = IsNewBarFast(sym, g_TFZone,    g_LastBarTimeZona[i]);
      bool newGatillo = IsNewBarFast(sym, g_TFTrigger, g_LastBarTimeGatillo[i]);
      if(newMacro || newZona)
         g_SmcAnalyzer[i].UpdateStructure(newMacro, newZona);

      if(newZona)
        {
         double dirActual = g_SmcAnalyzer[i].GetMacroDirection();
         if(dirActual != 0.0)
           {
            double slope = g_SmcAnalyzer[i].CalculateRegressionSlope(20, PERIOD_M15);
            double atr   = g_SmcAnalyzer[i].GetATR(14);
            double mom   = g_SmcAnalyzer[i].CalculateMomentum(20, PERIOD_M15);
            double flow  = g_SmcAnalyzer[i].CalculateVolumeFlow(20, PERIOD_M15);
            double adx   = g_SmcAnalyzer[i].GetADX();
            double rsi   = g_SmcAnalyzer[i].GetRSI();
            // Calcular las 6 nuevas features con valores reales
            double deltaVol = 0.0, spreadDev = 0.0, smcRatio = 0.0, relStrength = 0.0, normVolatility = 0.0, volRatio = 1.0;
            // deltaVol: diferencia de volumen respecto a la media de las últimas 20 velas M15
            long tickVolM15[];
            if(CopyTickVolume(sym, PERIOD_M15, 1, 20, tickVolM15) == 20)
              {
               double avgVol = 0;
               for(int k=0;k<20;k++)
                  avgVol += (double)tickVolM15[k];
               avgVol/=20;
               if(avgVol>0)
                  deltaVol = ((double)tickVolM15[0] - avgVol)/avgVol;
              }
            // spreadDev: desviación del spread respecto a su media reciente (simplificado: spread actual vs promedio móvil)
            double avgSpread = 0;
            for(int k=0;k<20;k++)
               avgSpread += (double)SymbolInfoInteger(sym, SYMBOL_SPREAD);
            avgSpread/=20;
            if(avgSpread>0)
               spreadDev = ((double)spread - avgSpread)/avgSpread;
            // smcRatio: ratio de mitigación del OB
            double priceMid = (SymbolInfoDouble(sym, SYMBOL_ASK) + SymbolInfoDouble(sym, SYMBOL_BID))/2;
            smcRatio = g_SmcAnalyzer[i].GetOBMitigationRatio(priceMid, dirActual > 0);
            // relStrength: fuerza relativa (precio vs MA H4)
            double maH4[];
            if(CopyClose(sym, PERIOD_H4, 20, 1, maH4) == 1)
               relStrength = (SymbolInfoDouble(sym, SYMBOL_BID) - maH4[0]) / (atr + 1e-9);
            // normVolatility: volatilidad normalizada
            normVolatility = atr / SymbolInfoDouble(sym, SYMBOL_BID);
            // volRatio: atr M1 / atr H4
            double atr1v[1], atrH4v[1];
            if(CopyBuffer(g_HandleATR_M1[i],0,0,1,atr1v)==1 && CopyBuffer(g_HandleATR_H4[i],0,0,1,atrH4v)==1 && atrH4v[0]!=0.0)
               volRatio = atr1v[0]/atrH4v[0];

            g_KnnClassifier[i].AddSample(slope, atr, mom, flow, adx, rsi, (int)dirActual,
                                         deltaVol, spreadDev, smcRatio, relStrength, normVolatility, volRatio);
            if(g_KnnClassifier[i].IsAutoSavePending())
              {
               g_KnnClassifier[i].SaveState("Arion\\KNN_"+g_Assets[i]+".bin");
               g_KnnClassifier[i].ResetAutoSaveFlag();
              }
           }
        }

      if(!newGatillo || !allowSignals)
         continue;
      double dir = g_SmcAnalyzer[i].GetMacroDirection();
      if(dir == 0.0)
         continue;

      double ask = SymbolInfoDouble(sym, SYMBOL_ASK), bid = SymbolInfoDouble(sym, SYMBOL_BID);
      double price = (dir > 0) ? ask : bid, point = SymbolInfoDouble(sym, SYMBOL_POINT);

      bool recalculate = false;
      double pipsDisplacement = InpMinPipsDisplacement * point;
      datetime currentBarTime = (datetime)SeriesInfoInteger(sym, g_TFTrigger, SERIES_LASTBAR_DATE);
      if(currentBarTime > g_LastCalcBarTime[i])
         recalculate = true;
      if(!recalculate && MathAbs(price - g_LastCalcPrice[i]) >= pipsDisplacement)
         recalculate = true;
      if(!recalculate && MathAbs(dir - g_LastMacroDirection[i]) > 1e-10)
         recalculate = true;

      double probONNX = g_LastProbONNX[i], probKNN = g_LastProbKNN[i];
      bool zoneMitigated = g_LastMitigatedZone[i];
      double mitigationRatio = g_LastMitigationRatio[i], relVolatility = 1.0;

      if(recalculate)
        {
         zoneMitigated = g_SmcAnalyzer[i].IsOBMitigated(price, dir > 0) || g_SmcAnalyzer[i].IsFVGMitigated(price, dir > 0);
         mitigationRatio = g_SmcAnalyzer[i].GetOBMitigationRatio(price, dir > 0);
         double atr1v[1], atrH4v[1];
         if(g_HandleATR_M1[i] != INVALID_HANDLE && g_HandleATR_H4[i] != INVALID_HANDLE)
            if(CopyBuffer(g_HandleATR_M1[i],0,0,1,atr1v)==1 && CopyBuffer(g_HandleATR_H4[i],0,0,1,atrH4v)==1 && atrH4v[0]!=0.0)
               relVolatility = atr1v[0]/atrH4v[0];

         double slope_1 = g_SmcAnalyzer[i].CalculateRegressionSlope(20, PERIOD_M1);
         double atr_1   = g_SmcAnalyzer[i].GetATR(14);
         double mom_1   = g_SmcAnalyzer[i].CalculateMomentum(20, PERIOD_M1);
         double flow_1  = g_SmcAnalyzer[i].CalculateVolumeFlow(20, PERIOD_M1);
         double adx_1   = g_SmcAnalyzer[i].GetADX();
         double rsi_1   = g_SmcAnalyzer[i].GetRSI();

         // Calcular las 6 features nuevas para el ONNX (misma lógica que en AddSample)
         double deltaVol = 0.0, spreadDev = 0.0, smcRatio = 0.0, relStrength = 0.0, normVolatility = 0.0, volRatio = 1.0;
           {
            long tickVolM1[];
            if(CopyTickVolume(sym, PERIOD_M1, 1, 20, tickVolM1) == 20)
              {
               double avgVol = 0;
               for(int k=0;k<20;k++)
                  avgVol += (double)tickVolM1[k];
               avgVol/=20;
               if(avgVol>0)
                  deltaVol = ((double)tickVolM1[0] - avgVol)/avgVol;
              }
           }
           {
            double avgSpread = 0;
            for(int k=0;k<20;k++)
               avgSpread += (double)SymbolInfoInteger(sym, SYMBOL_SPREAD);
            avgSpread/=20;
            if(avgSpread>0)
               spreadDev = ((double)spread - avgSpread)/avgSpread;
           }
         smcRatio = mitigationRatio;
           { double maH4[]; if(CopyClose(sym, PERIOD_H4, 20, 1, maH4) == 1) relStrength = (SymbolInfoDouble(sym, SYMBOL_BID) - maH4[0]) / (atr_1 + 1e-9); }
         normVolatility = atr_1 / SymbolInfoDouble(sym, SYMBOL_BID);
         volRatio = relVolatility;

         double probBuy = 0.5, probSell = 0.5;
         if(g_StatisticalFilter[i].IsModelLoaded())
           {
            g_StatisticalFilter[i].CalculateVolumeZScore();
            float inputs[12];
            inputs[0] = (float)slope_1;
            inputs[1] = (float)atr_1;
            inputs[2] = (float)mom_1;
            inputs[3] = (float)flow_1;
            inputs[4] = (float)adx_1;
            inputs[5] = (float)rsi_1;
            inputs[6] = (float)deltaVol;
            inputs[7] = (float)spreadDev;
            inputs[8] = (float)smcRatio;
            inputs[9] = (float)relStrength;
            inputs[10] = (float)normVolatility;
            inputs[11] = (float)volRatio;
            if(!g_StatisticalFilter[i].ExecuteXGBoostPrediction(inputs, probBuy, probSell))
              {
               probBuy = 0.5;
               probSell = 0.5;
              }
           }
         probONNX = (dir > 0) ? probBuy : probSell;
         probKNN  = g_KnnClassifier[i].CalculateKNNProbability(slope_1, atr_1, mom_1, flow_1, adx_1, rsi_1,
                    deltaVol, spreadDev, smcRatio, relStrength, normVolatility, volRatio, 15);

         g_LastCalcBarTime[i]     = currentBarTime;
         g_LastCalcPrice[i]       = price;
         g_LastProbONNX[i]        = probONNX;
         g_LastProbKNN[i]         = probKNN;
         g_LastMitigatedZone[i]   = zoneMitigated;
         g_LastMitigationRatio[i] = mitigationRatio;
         g_LastMacroDirection[i]  = dir;
        }

      double score = g_SignalFilter[i].ProcessSignal((int)dir, probONNX, probKNN, zoneMitigated, mitigationRatio, relVolatility);
      if(score < InpApprovalThreshold)
         continue;

      double slPoints = 200.0;
        { double atr1v[1]; if(g_HandleATR_M1[i] != INVALID_HANDLE && CopyBuffer(g_HandleATR_M1[i],0,0,1,atr1v)==1 && atr1v[0]>0) slPoints = atr1v[0] * InpATRMultiplierSL / point; }
      double tpPoints;
      double tpLevel = g_SmcAnalyzer[i].FindOppositeLiquidity(price, dir > 0);
      if(tpLevel > 0.0)
        {
         double tpDist = (dir > 0) ? (tpLevel - price) : (price - tpLevel);
         tpPoints = tpDist / point;
         if((tpPoints / slPoints) < 2.0)
            continue;
        }
      else
         tpPoints = slPoints * InpRRRatio;

      double lot = g_RiskManager[i].CalculateLots(InpRiskPercentage, slPoints);
      if(lot <= 0.0)
         continue;
      if(!g_GlobalRiskManager.ConsumeCredit())
         continue;

      ENUM_ORDER_TYPE type = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(!g_Executor[i].SendMarketOrder(type, lot, slPoints, tpPoints, "Arion_"+sym))
         g_GlobalRiskManager.ReturnCredit();
     }
  }

//+------------------------------------------------------------------+
//| OnTradeTransaction                                               |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
  {
   for(int i=0; i<g_TotalAssets; i++)
      if(CheckPointer(g_Executor[i]) == POINTER_DYNAMIC)
         g_Executor[i].ProcessTransaction(trans, request, result);
   if(trans.type == TRADE_TRANSACTION_ORDER_ADD || trans.type == TRADE_TRANSACTION_ORDER_UPDATE || trans.type == TRADE_TRANSACTION_ORDER_DELETE)
     {
      PrintFormat("Transaction: %s | Order: %d | %s | Retcode: %d | Price: %.5f | Vol: %.2f", EnumToString(trans.type), trans.order, trans.symbol, result.retcode, result.price, result.volume);
      if(result.retcode == TRADE_RETCODE_DONE)
        {
         string typeStr = (trans.type == TRADE_TRANSACTION_ORDER_ADD) ? "OPEN" : (trans.type == TRADE_TRANSACTION_ORDER_DELETE) ? "CLOSE" : "UPDATE";
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
         int n = ArraySize(g_Trades);
         ArrayResize(g_Trades, n+1);
         g_Trades[n].profit = profit;
         g_Trades[n].balance = AccountInfoDouble(ACCOUNT_BALANCE);
         g_Trades[n].closeTime = TimeCurrent();
         if(g_GlobalRiskManager.CanOpenTrade())
            g_GlobalRiskManager.ReturnCredit();
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OnTesterInit()
  {
   ParameterSetRange("InpWeightONNX", false, InpWeightONNX, 20.0, 5.0, 40.0);
   ParameterSetRange("InpWeightKNN", false, InpWeightKNN, 15.0, 5.0, 35.0);
   ParameterSetRange("InpWeightSMC", false, InpWeightSMC, 15.0, 5.0, 35.0);
   ParameterSetRange("InpWeightContext", false, InpWeightContext, 5.0, 5.0, 25.0);
   return 0;
  }
void OnTesterDeinit() { }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double OnTester()
  {
   double sharpe = Metrics::CalculateSharpeRatio(g_Trades), pf = Metrics::CalculateProfitFactor(g_Trades), dd = Metrics::CalculateMaxDrawdown(g_Trades);
   double score = sharpe * pf * (1.0 - dd);
   int h = FileOpen("Arion\\WF_Report.csv", FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI);
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
