//+------------------------------------------------------------------+
//|                                                  Dashboard.mqh   |
//|                        Arion - Panel Institucional Global        |
//|                        Autor: Alexy Hernandez                    |
//|                        Version: 1.0                              |
//|        Copyright (c) 2025 Alexy Hernandez. Todos los derechos    |
//|        reservados.                                               |
//|        * COLUMNAS: SYMBOL, IA, CHOP, VOL, SMC, SP, APR, NEWS    |
//|        * Exportaci�n diaria a Arion\DASHBOARD\[Fecha].csv       |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernandez. Todos los derechos reservados."
#property link      "https://github.com/axgeovax"
#property version   "1.0"
#property strict

#ifndef DASHBOARD_MQH
#define DASHBOARD_MQH

#include "NewsFilter.mqh"

struct SymbolMetrics
  {
   string            symbol;
   long              spread;
   bool              newsBlocked;
   int               decoupling;      // se mantiene por compatibilidad pero no se muestra
   double            iaSignal;
   double            choppiness;
   double            volatility;      // Ratio ATR M15 / ATR H4 (valor real)
   int               activeOBs;
   int               activeFVGs;
   int               direction;       // 1=buy, -1=sell, 0=neutral
   double            approvalPct;     // Approval percentage for APR column
  };

struct DashboardInfo
  {
   double            balance;
   double            equity;
   double            dayStartEquity;
   int               totalOps;
   double            drawdown;
   double            maxDailyDD;
   double            avgSpread;
   bool              newsBlocked;
   double            avgProbONNX;
   double            avgProbKNN;
   double            avgChoppiness;
   double            avgVolatility;
   int               totalActiveOBs;
   int               totalActiveFVGs;
   bool              onnxUpdated;
   int               decouplingCount;

   SymbolMetrics     symbolMetrics[];
  };

//+------------------------------------------------------------------+
//| Clase Dashboard                                                   |
//+------------------------------------------------------------------+
class Dashboard
  {
private:
   static const string PREFIX;
   bool              m_created;
   int               m_baseX;
   int               m_baseY;
   int               m_width;
   int               m_totalSymbols;

   NewsFilter*       m_newsFilter;

   double            m_cachedChoppiness;
   double            m_cachedVolatility;
   datetime          m_lastBarUpdate;

   string            m_txtCache[];
   color             m_clrCache[];
   int               m_labelCount;

   int               m_lastAutoExportDay;
   bool              m_needReposition;

   double            m_spreadGoodThreshold;
   double            m_spreadBadThreshold;

   void              CreateLabel(string name, int x, int y, string text, color clr=clrSilver, int fontSize=8, string font="Consolas");
   void              CreateBackground(string name, int x, int y, int width, int height, color clr=(color)0x141414);
   color             ColorBySign(double value);
   color             ColorByLowerIsBetter(double value, double goodThreshold, double badThreshold);
   color             ColorByHigherIsBetter(double value, double badThreshold, double goodThreshold);
   void              RepositionAll();
   int               ComputeTotalLabels();

public:
                     Dashboard() : m_created(false), m_baseX(15), m_baseY(20), m_width(460), m_newsFilter(NULL),
                     m_lastAutoExportDay(0), m_needReposition(false), m_totalSymbols(10),
                     m_cachedChoppiness(50.0), m_cachedVolatility(1.0), m_lastBarUpdate(0),
                     m_labelCount(0), m_spreadGoodThreshold(10.0), m_spreadBadThreshold(30.0)
     {
      ArrayResize(m_txtCache, 0);
      ArrayResize(m_clrCache, 0);
     }
                    ~Dashboard() { Remove(); }

   bool              Initialize(int totalSymbols = 10);
   void              Update(const DashboardInfo &info);
   void              Remove();
   bool              UpdateLabel(int idx, string name, string text, color clr);

   void              SetNewsFilter(NewsFilter* filter) { m_newsFilter = filter; }
   void              InvalidateCache() { m_lastBarUpdate = 0; }

   void              SetSpreadThresholds(double good, double bad) { m_spreadGoodThreshold = good; m_spreadBadThreshold = bad; }

   bool              ExportDailySnapshot(const DashboardInfo &info, string filePath = "Arion\\DASHBOARD\\");
   void              TryAutoExport(const DashboardInfo &info);

   void              OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam);
  };

const string Dashboard::PREFIX = "ArionDash_";

//+------------------------------------------------------------------+
//| Colores                                                           |
//+------------------------------------------------------------------+
color Dashboard::ColorBySign(double value)
  {
   if(value > 0.0001)
      return clrLime;
   if(value < -0.0001)
      return clrRed;
   return clrGray;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
color Dashboard::ColorByLowerIsBetter(double value, double goodThreshold, double badThreshold)
  {
   if(value == 0.0)
      return clrGray;
   if(value <= goodThreshold)
      return clrLime;
   if(value >= badThreshold)
      return clrRed;
   return clrGray;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
color Dashboard::ColorByHigherIsBetter(double value, double badThreshold, double goodThreshold)
  {
   if(value == 0.0)
      return clrGray;
   if(value >= goodThreshold)
      return clrLime;
   if(value <= badThreshold)
      return clrRed;
   return clrGray;
  }

//+------------------------------------------------------------------+
//| Crea una etiqueta                                                 |
//+------------------------------------------------------------------+
void Dashboard::CreateLabel(string name, int x, int y, string text, color clr, int fontSize, string font)
  {
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 1);
  }

//+------------------------------------------------------------------+
//| Crea un fondo rectangular                                         |
//+------------------------------------------------------------------+
void Dashboard::CreateBackground(string name, int x, int y, int width, int height, color clr)
  {
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 0);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
  }

//+------------------------------------------------------------------+
//| Calcula cu�ntas etiquetas se crear�n                              |
//+------------------------------------------------------------------+
int Dashboard::ComputeTotalLabels()
  {
// 1 t�tulo + 10 m�tricas globales + 1 separador + 8 cabeceras de columna + (8 columnas por s�mbolo)
   return 20 + m_totalSymbols * 8;
  }

//+------------------------------------------------------------------+
//| Inicializa el panel                                               |
//+------------------------------------------------------------------+
bool Dashboard::Initialize(int totalSymbols)
  {
   if(m_created)
      return true;

   m_totalSymbols = totalSymbols;
   m_labelCount = ComputeTotalLabels();
   ArrayResize(m_txtCache, m_labelCount);
   ArrayResize(m_clrCache, m_labelCount);
   for(int i = 0; i < m_labelCount; i++)
     {
      m_txtCache[i] = "";
      m_clrCache[i] = clrNONE;
     }

   const int lineHeight = 12;
   const int headerLines = 2;
   const int separatorLines = 1;
   const int tableHeaderLines = 1;
   const int totalLines = headerLines + separatorLines + tableHeaderLines + m_totalSymbols;
   const int bgHeight = totalLines * lineHeight;

   int x = m_baseX;
   int y = m_baseY;

   CreateBackground(PREFIX+"Bg", x + m_width, y, m_width+6, bgHeight, (color)0x1A1A1A);
   CreateBackground(PREFIX+"Border", x + m_width - 2, y, m_width + 10, bgHeight + 4, (color)0x333333);

// T�tulo
   CreateLabel(PREFIX+"Title", x + m_width - 15, y, "ARION 2.0 - TABLE DASHBOARD", clrTurquoise, 9, "Consolas");
   y += lineHeight;

// Cabecera global (10 labels)
   CreateLabel(PREFIX+"GOps",    x + m_width - 15, y, "OPS:", clrSilver, 8);
   CreateLabel(PREFIX+"G_Ops",   x + m_width - 45, y, "0", clrWhite, 8);
   CreateLabel(PREFIX+"GDay",    x + m_width - 80, y, "DAY:", clrSilver, 8);
   CreateLabel(PREFIX+"G_Day",   x + m_width - 115, y, "$0.00", clrGray, 8);
   CreateLabel(PREFIX+"GGain",   x + m_width - 185, y, "GAIN:", clrSilver, 8);
   CreateLabel(PREFIX+"G_Gain",  x + m_width - 220, y, "0.0%", clrGray, 8);
   CreateLabel(PREFIX+"GDD",     x + m_width - 270, y, "DD:", clrSilver, 8);
   CreateLabel(PREFIX+"G_DD",    x + m_width - 295, y, "0.0/5.0%", clrGray, 8);
   CreateLabel(PREFIX+"GModel",  x + m_width - 365, y, "MODEL:", clrSilver, 8);
   CreateLabel(PREFIX+"G_Model", x + m_width - 410, y, "STATIC", clrSilver, 8);
   y += lineHeight;

// Separador
   CreateLabel(PREFIX+"Sep", x + m_width - 15, y, "------------------------------------------------------------------------------------------", clrGray, 8);
   y += lineHeight;

// Cabeceras de columna (nuevo orden, sin DEC, con APR)
   CreateLabel(PREFIX+"ColSym",  x + m_width - 15, y, "SYMBOL", clrYellow, 8);
   CreateLabel(PREFIX+"ColIA",   x + m_width - 80, y, "IA", clrYellow, 8);
   CreateLabel(PREFIX+"ColChop", x + m_width - 130, y, "CHOP", clrYellow, 8);
   CreateLabel(PREFIX+"ColVol",  x + m_width - 180, y, "VOL", clrYellow, 8);
   CreateLabel(PREFIX+"ColSMC",  x + m_width - 230, y, "SMC", clrYellow, 8);
   CreateLabel(PREFIX+"ColSP",   x + m_width - 300, y, "SP", clrYellow, 8);
   CreateLabel(PREFIX+"ColAPR",  x + m_width - 350, y, "APR", clrYellow, 8);   // NUEVA COLUMNA
   CreateLabel(PREFIX+"ColNews", x + m_width - 400, y, "NEWS", clrYellow, 8);
   y += lineHeight;

// Filas de s�mbolos
   for(int i = 0; i < m_totalSymbols; i++)
     {
      string prefix = PREFIX + "Sym" + IntegerToString(i) + "_";
      CreateLabel(prefix + "Name", x + m_width - 15, y, "--------", clrSilver, 8);
      CreateLabel(prefix + "IA",   x + m_width - 80, y, "0%", clrGray, 8);
      CreateLabel(prefix + "Chop", x + m_width - 130, y, "0", clrGray, 8);
      CreateLabel(prefix + "Vol",  x + m_width - 180, y, "0x", clrGray, 8);
      CreateLabel(prefix + "SMC",  x + m_width - 230, y, "0/0", clrWhite, 8);
      CreateLabel(prefix + "SP",   x + m_width - 300, y, "0", clrGray, 8);
      CreateLabel(prefix + "APR",  x + m_width - 350, y, "0%", clrGray, 8);   // NUEVA COLUMNA
      CreateLabel(prefix + "News", x + m_width - 400, y, "OK", clrLime, 8);
      y += lineHeight;
     }

   m_created = true;
   ChartRedraw(0);
   return true;
  }

//+------------------------------------------------------------------+
//| Actualiza una etiqueta si cambi�                                  |
//+------------------------------------------------------------------+
bool Dashboard::UpdateLabel(int idx, string name, string text, color clr)
  {
   if(idx < 0 || idx >= m_labelCount)
      return false;

   if(m_txtCache[idx] != text || m_clrCache[idx] != clr)
     {
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      m_txtCache[idx] = text;
      m_clrCache[idx] = clr;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Refresca el panel                                                 |
//+------------------------------------------------------------------+
void Dashboard::Update(const DashboardInfo &info)
  {
   if(!m_created)
      return;

   if(m_needReposition)
     {
      RepositionAll();
      m_needReposition = false;
     }

   datetime currentBar = (datetime)SeriesInfoInteger(_Symbol, PERIOD_M1, SERIES_LASTBAR_DATE);
   if(currentBar != m_lastBarUpdate)
     {
      m_cachedChoppiness = info.avgChoppiness;
      m_cachedVolatility = info.avgVolatility;
      m_lastBarUpdate = currentBar;
     }

   double dayProfit = info.equity - info.dayStartEquity;
   double gainPct = (info.dayStartEquity > 0) ? (dayProfit / info.dayStartEquity) * 100.0 : 0.0;
   if(gainPct > 10000.0 || gainPct < -10000.0)
      gainPct = 0.0;

   bool changed = false;
   int cacheIdx = 0;

// Cabecera global
   changed |= UpdateLabel(cacheIdx++, PREFIX+"G_Ops", IntegerToString(info.totalOps), clrWhite);
   string dayText = (dayProfit>=0?"+$":"-$") + DoubleToString(MathAbs(dayProfit), 2);
   changed |= UpdateLabel(cacheIdx++, PREFIX+"G_Day", dayText, ColorBySign(dayProfit));
   string gainText = DoubleToString(gainPct, 1) + "%";
   changed |= UpdateLabel(cacheIdx++, PREFIX+"G_Gain", gainText, ColorBySign(gainPct));
   string ddText = DoubleToString(info.drawdown,1) + "/" + DoubleToString(info.maxDailyDD,1) + "%";
   changed |= UpdateLabel(cacheIdx++, PREFIX+"G_DD", ddText, ColorByLowerIsBetter(info.drawdown, 1.0, 3.0));
   string modelText = info.onnxUpdated ? "EVOLUTIVE" : "STATIC";
   changed |= UpdateLabel(cacheIdx++, PREFIX+"G_Model", modelText, info.onnxUpdated ? clrLime : clrSilver);

// Tabla de s�mbolos (nuevo orden)
   for(int i = 0; i < m_totalSymbols && i < ArraySize(info.symbolMetrics); i++)
     {
      string prefix = PREFIX + "Sym" + IntegerToString(i) + "_";
      SymbolMetrics sym = info.symbolMetrics[i];

      string name = StringSubstr(sym.symbol, 0, 6);
      changed |= UpdateLabel(cacheIdx++, prefix + "Name", name, clrWhite);

      // IA
      string iaText = DoubleToString(sym.iaSignal * 100.0, 0) + "%";
      changed |= UpdateLabel(cacheIdx++, prefix + "IA", iaText, ColorByHigherIsBetter(sym.iaSignal, 0.40, 0.65));

      // CHOP
      string chopText = DoubleToString(sym.choppiness, 0);
      double validChop = MathMax(0.0, MathMin(100.0, sym.choppiness));
      color chopColor = (validChop == 50.0) ? clrGray : (validChop >= 38.2 && validChop <= 61.8) ? clrLime : clrRed;
      changed |= UpdateLabel(cacheIdx++, prefix + "Chop", chopText, chopColor);

      // VOL
      string volText = DoubleToString(sym.volatility, 2) + "x";
      double validVol = sym.volatility;
      color volColor = (validVol >= 0.7 && validVol <= 1.5) ? clrLime : clrRed;
      changed |= UpdateLabel(cacheIdx++, prefix + "Vol", volText, volColor);

      // SMC
      string smcText = "OB:" + IntegerToString(sym.activeOBs) + "/FVG:" + IntegerToString(sym.activeFVGs);
      changed |= UpdateLabel(cacheIdx++, prefix + "SMC", smcText, clrWhite);

      // SP
      string spText = IntegerToString((int)sym.spread);
      changed |= UpdateLabel(cacheIdx++, prefix + "SP", spText, ColorByLowerIsBetter((double)sym.spread, m_spreadGoodThreshold, m_spreadBadThreshold));

      // APR (NUEVO)
      string aprText;
      color aprColor;
      if(sym.direction == 0)
        {
         aprText = "N/A";
         aprColor = clrGray;

        }
      else
        {
         string arrow = (sym.direction > 0) ? "BUY" : (sym.direction < 0) ? "SELL" : "";
         aprColor = (sym.direction > 0) ? clrLime : (sym.direction < 0) ? clrRed : clrGray;
         aprText = arrow + DoubleToString(sym.approvalPct, 0) + "%";

        }

      changed |= UpdateLabel(cacheIdx++, prefix + "APR", aprText, aprColor);

      // NEWS
      string newsText = sym.newsBlocked ? "BLOCKED" : "OK";
      changed |= UpdateLabel(cacheIdx++, prefix + "News", newsText, sym.newsBlocked ? clrRed : clrLime);
     }

   if(changed || m_needReposition)
      ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Reposiciona todos los elementos                                   |
//+------------------------------------------------------------------+
void Dashboard::RepositionAll()
  {
   if(!m_created)
      return;

   const int lineHeight = 12;
   int x = m_baseX;
   int y = m_baseY;

   if(ObjectFind(0, PREFIX+"Title") >= 0)
     {
      ObjectSetInteger(0, PREFIX+"Title", OBJPROP_XDISTANCE, x + m_width - 15);
      ObjectSetInteger(0, PREFIX+"Title", OBJPROP_YDISTANCE, y);
     }
   y += lineHeight;

   string globalLabels[] = {"GOps","G_Ops","GDay","G_Day","GGain","G_Gain","GDD","G_DD","GModel","G_Model"};
   int xPos[] = {m_width-15, m_width-45, m_width-80, m_width-115, m_width-185, m_width-220, m_width-270, m_width-295, m_width-365, m_width-410};
   for(int i=0; i<ArraySize(globalLabels); i++)
     {
      string objName = PREFIX+globalLabels[i];
      if(ObjectFind(0, objName) >= 0)
        {
         ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x + xPos[i]);
         ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
        }
     }
   y += lineHeight;

   if(ObjectFind(0, PREFIX+"Sep") >= 0)
     {
      ObjectSetInteger(0, PREFIX+"Sep", OBJPROP_XDISTANCE, x + m_width - 15);
      ObjectSetInteger(0, PREFIX+"Sep", OBJPROP_YDISTANCE, y);
     }
   y += lineHeight;

   string colLabels[] = {"ColSym","ColIA","ColChop","ColVol","ColSMC","ColSP","ColAPR","ColNews"};
   int colXPos[] = {m_width-15, m_width-80, m_width-130, m_width-180, m_width-230, m_width-300, m_width-350, m_width-400};
   for(int i=0; i<ArraySize(colLabels); i++)
     {
      string objName = PREFIX+colLabels[i];
      if(ObjectFind(0, objName) >= 0)
        {
         ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x + colXPos[i]);
         ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
        }
     }
   y += lineHeight;

   for(int i = 0; i < m_totalSymbols; i++)
     {
      string prefix = PREFIX + "Sym" + IntegerToString(i) + "_";
      string fields[] = {"Name","IA","Chop","Vol","SMC","SP","APR","News"};
      int fieldXPos[] = {m_width-15, m_width-80, m_width-130, m_width-180, m_width-230, m_width-300, m_width-350, m_width-400};
      for(int j = 0; j < ArraySize(fields); j++)
        {
         string objName = prefix+fields[j];
         if(ObjectFind(0, objName) >= 0)
           {
            ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x + fieldXPos[j]);
            ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
           }
        }
      y += lineHeight;
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Dashboard::Remove()
  {
   ObjectsDeleteAll(0, PREFIX);
   m_created = false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool Dashboard::ExportDailySnapshot(const DashboardInfo &info, string filePath = "Arion\\DASHBOARD\\")
  {
// Crear carpeta si no existe
   FolderCreate("Arion\\DASHBOARD");

   string fullPath = filePath + TimeToString(TimeCurrent(), TIME_DATE);
   StringReplace(fullPath, ".", "-");   // 2025.06.17 -> 2025-06-17
   fullPath = fullPath +".csv";
   
   int handle = FileOpen(fullPath+".csv", FILE_CSV|FILE_WRITE|FILE_ANSI, ";");
   if(handle == INVALID_HANDLE)
      return false;

   datetime now = TimeCurrent();
   FileWrite(handle, "Date", "Time", "Balance", "Equity", "DayProfit", "Gain%", "Drawdown%", "TotalOps", "AvgSpread", "NewsBlocked", "AvgIA%", "ModelUpdated");

   double dayProfit = info.equity - info.dayStartEquity;
   double gainPct = (info.dayStartEquity > 0) ? (dayProfit / info.dayStartEquity) * 100.0 : 0.0;
   if(gainPct > 10000.0 || gainPct < -10000.0)
      gainPct = 0.0;
   double knnNorm = (info.avgProbKNN + 1.0) / 2.0;
   double iaAvg = (info.avgProbONNX + knnNorm) / 2.0;

   FileWrite(handle,
             TimeToString(now, TIME_DATE),
             TimeToString(now, TIME_MINUTES),
             DoubleToString(info.balance, 2),
             DoubleToString(info.equity, 2),
             DoubleToString(dayProfit, 2),
             DoubleToString(gainPct, 2),
             DoubleToString(info.drawdown, 2),
             IntegerToString(info.totalOps),
             DoubleToString(info.avgSpread, 1),
             info.newsBlocked ? "BLOCKED" : "OK",
             DoubleToString(iaAvg * 100.0, 1),
             info.onnxUpdated ? "EVOLUTIVE" : "STATIC");

   FileWrite(handle, "");
   FileWrite(handle, "SYMBOL", "SPREAD", "NEWS_BLOCKED", "IA_SIGNAL%", "CHOPPINESS", "VOLATILITY", "ACTIVE_OB", "ACTIVE_FVG", "APPROVAL%");

   for(int i = 0; i < ArraySize(info.symbolMetrics); i++)
     {
      SymbolMetrics sym = info.symbolMetrics[i];
      FileWrite(handle,
                sym.symbol,
                IntegerToString((int)sym.spread),
                sym.newsBlocked ? "BLOCKED" : "OK",
                DoubleToString(sym.iaSignal * 100.0, 1),
                DoubleToString(sym.choppiness, 1),
                DoubleToString(sym.volatility, 2),
                IntegerToString(sym.activeOBs),
                IntegerToString(sym.activeFVGs),
                DoubleToString(sym.approvalPct, 1));
     }

   FileClose(handle);
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Dashboard::TryAutoExport(const DashboardInfo &info)
  {
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.day != m_lastAutoExportDay)
     {
      m_lastAutoExportDay = dt.day;
      ExportDailySnapshot(info, "Arion\\DASHBOARD\\");
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Dashboard::OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_CHART_CHANGE)
      m_needReposition = true;
  }

#endif // DASHBOARD_MQH
//+------------------------------------------------------------------+
