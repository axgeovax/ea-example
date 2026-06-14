//+------------------------------------------------------------------+
//|                                                  Dashboard.mqh   |
//|                        Arion - Panel Institucional Global        |
//|                        Autor: Alexy Hernández                    |
//|                        Versión: 1.0                              |
//|        Copyright (c) 2025 Alexy Hernández. Todos los derechos    |
//|        reservados.                                               |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernández. Todos los derechos reservados."
#property link      "https://github.com/axgeovax"
#property version   "1.0"
#property strict

#ifndef DASHBOARD_MQH
#define DASHBOARD_MQH

//+------------------------------------------------------------------+
//| Estructura con los datos globales del panel                      |
//+------------------------------------------------------------------+
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
   int               decouplingCount;   // pares en desacople institucional
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

   void              CreateLabel(string name, int x, int y, string text, color clr=clrSilver, int fontSize=8, string font="Consolas");
   void              CreateBackground(string name, int x, int y, int width, int height, color clr=(color)0x141414);
   color             ColorBySign(double value);
   color             ColorByLowerIsBetter(double value, double goodThreshold, double badThreshold);
   color             ColorByHigherIsBetter(double value, double badThreshold, double goodThreshold);

public:
                     Dashboard() : m_created(false), m_baseX(10), m_baseY(20), m_width(180) {}
                    ~Dashboard() { Remove(); }

   bool              Initialize();
   void              Update(const DashboardInfo &info);
   void              Remove();
  };

const string Dashboard::PREFIX = "ArionDash_";

//+------------------------------------------------------------------+
//| Colores dinámicos                                                 |
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
//| Inicializar panel                                                 |
//+------------------------------------------------------------------+
bool Dashboard::Initialize()
  {
   if(m_created)
      return true;

   int lineHeight = 14;
   int totalLines = 17;   // una línea extra para DEC
   int bgHeight = totalLines * lineHeight + 35;

   int xLabel = m_baseX + m_width - 5;
   int xValue = m_baseX + 100;
   int y = m_baseY;

   CreateBackground(PREFIX+"Bg", m_baseX + m_width, y - 5, m_width, bgHeight, (color)0x1A1A1A);
   CreateBackground(PREFIX+"Border", m_baseX + m_width, y - 5, m_width + 4, bgHeight + 4, (color)0x333333);

   CreateLabel(PREFIX+"Title", xLabel, y, "ARION GLOBAL DASHBOARD", clrTurquoise, 9, "Consolas");
   y += lineHeight;
   CreateLabel(PREFIX+"Sep",   xLabel, y, "==========================", clrTurquoise, 8);
   y += lineHeight;

// ACCOUNT
   CreateLabel(PREFIX+"Sec1", xLabel, y, "ACCOUNT", clrYellow, 8);
   y += lineHeight;
   CreateLabel(PREFIX+"LOps", xLabel, y, "OPS:");
   CreateLabel(PREFIX+"VOps", xValue, y, "0", clrWhite);
   y += lineHeight;
   CreateLabel(PREFIX+"LDay", xLabel, y, "DAY:");
   CreateLabel(PREFIX+"VDay", xValue, y, "$0.00", clrGray);
   y += lineHeight;
   CreateLabel(PREFIX+"LGain",xLabel, y, "GAIN:");
   CreateLabel(PREFIX+"VGain",xValue, y, "0.00%", clrGray);
   y += lineHeight;

// RISK
   CreateLabel(PREFIX+"Sec2", xLabel, y, "RISK", clrYellow, 8);
   y += lineHeight;
   CreateLabel(PREFIX+"LDD",  xLabel, y, "DD:");
   CreateLabel(PREFIX+"VDD",  xValue, y, "0.0/0.0%", clrGray);
   y += lineHeight;

// MARKET
   CreateLabel(PREFIX+"Sec3", xLabel, y, "MARKET", clrYellow, 8);
   y += lineHeight;
   CreateLabel(PREFIX+"LSP",  xLabel, y, "SP:");
   CreateLabel(PREFIX+"VSP",  xValue, y, "0", clrGray);
   y += lineHeight;
   CreateLabel(PREFIX+"LNews",xLabel, y, "NEWS:");
   CreateLabel(PREFIX+"VNews",xValue, y, "OK", clrLime);
   y += lineHeight;
   CreateLabel(PREFIX+"LDec", xLabel, y, "DEC:");
   CreateLabel(PREFIX+"VDec", xValue, y, "0", clrGray);
   y += lineHeight;

// CORE IA
   CreateLabel(PREFIX+"Sec4", xLabel, y, "CORE IA", clrYellow, 8);
   y += lineHeight;
   CreateLabel(PREFIX+"LIA",  xLabel, y, "IA:");
   CreateLabel(PREFIX+"VIA",  xValue, y, "0.0%", clrGray);
   y += lineHeight;
   CreateLabel(PREFIX+"LChop",xLabel, y, "CHOP:");
   CreateLabel(PREFIX+"VChop",xValue, y, "0.0", clrGray);
   y += lineHeight;
   CreateLabel(PREFIX+"LModel",xLabel, y, "MODEL:");
   CreateLabel(PREFIX+"VMod",  xValue, y, "STATIC", clrSilver);
   y += lineHeight;

// ANALYSIS
   CreateLabel(PREFIX+"Sec5", xLabel, y, "ANALYSIS", clrYellow, 8);
   y += lineHeight;
   CreateLabel(PREFIX+"LVol", xLabel, y, "VOL:");
   CreateLabel(PREFIX+"VVol", xValue, y, "0.00x", clrGray);
   y += lineHeight;
   CreateLabel(PREFIX+"LSMC", xLabel, y, "SMC:");
   CreateLabel(PREFIX+"VSMC", xValue, y, "0/0", clrWhite);

   m_created = true;
   ChartRedraw(0);
   return true;
  }

//+------------------------------------------------------------------+
//| Actualizar panel con datos globales                               |
//+------------------------------------------------------------------+
void Dashboard::Update(const DashboardInfo &info)
  {
   if(!m_created)
      return;

   double dayProfit = info.equity - info.dayStartEquity;
   double gainPct = (info.dayStartEquity > 0) ? (dayProfit / info.dayStartEquity) * 100.0 : 0.0;
   double knnNorm = (info.avgProbKNN + 1.0) / 2.0;
   double iaAvg = (info.avgProbONNX + knnNorm) / 2.0;

   ObjectSetString(0, PREFIX+"VOps",  OBJPROP_TEXT, IntegerToString(PositionsTotal()));

   ObjectSetString(0, PREFIX+"VDay",  OBJPROP_TEXT, (dayProfit>=0?"+$":"-$")+DoubleToString(MathAbs(dayProfit), 2));
   ObjectSetInteger(0,PREFIX+"VDay",  OBJPROP_COLOR, ColorBySign(dayProfit));

   ObjectSetString(0, PREFIX+"VGain", OBJPROP_TEXT, DoubleToString(gainPct, 2)+"%");
   ObjectSetInteger(0,PREFIX+"VGain", OBJPROP_COLOR, ColorBySign(gainPct));

   ObjectSetString(0, PREFIX+"VDD",   OBJPROP_TEXT, DoubleToString(info.drawdown,1)+"/"+DoubleToString(info.maxDailyDD,1)+"%");
   ObjectSetInteger(0,PREFIX+"VDD",   OBJPROP_COLOR, ColorByLowerIsBetter(info.drawdown, 0.5, 5.0));

   ObjectSetString(0, PREFIX+"VSP",   OBJPROP_TEXT, IntegerToString((int)info.avgSpread));
   ObjectSetInteger(0,PREFIX+"VSP",   OBJPROP_COLOR, ColorByLowerIsBetter(info.avgSpread, 10.0, 30.0));

   ObjectSetString(0, PREFIX+"VNews", OBJPROP_TEXT, info.newsBlocked ? "BLOCKED" : "OK");
   ObjectSetInteger(0,PREFIX+"VNews", OBJPROP_COLOR, info.newsBlocked ? clrRed : clrLime);

   ObjectSetString(0, PREFIX+"VDec",  OBJPROP_TEXT, IntegerToString(info.decouplingCount));
   ObjectSetInteger(0,PREFIX+"VDec",  OBJPROP_COLOR, info.decouplingCount > 0 ? clrRed : clrLime);

   ObjectSetString(0, PREFIX+"VIA",   OBJPROP_TEXT, DoubleToString(iaAvg * 100.0, 1) + "%");
   ObjectSetInteger(0,PREFIX+"VIA",   OBJPROP_COLOR, ColorByHigherIsBetter(iaAvg, 0.40, 0.65));

   double chop = info.avgChoppiness;
   color chopColor = (chop == 0.0) ? clrGray : (chop >= 38.2 && chop <= 61.8) ? clrLime : clrRed;
   ObjectSetString(0, PREFIX+"VChop", OBJPROP_TEXT, DoubleToString(chop, 1));
   ObjectSetInteger(0,PREFIX+"VChop", OBJPROP_COLOR, chopColor);

   ObjectSetString(0, PREFIX+"VMod",  OBJPROP_TEXT, info.onnxUpdated ? "EVOLUTIVE" : "STATIC");
   ObjectSetInteger(0,PREFIX+"VMod",  OBJPROP_COLOR, info.onnxUpdated ? clrLime : clrSilver);

   double vol = info.avgVolatility;
   color volColor = (vol == 0.0) ? clrGray : (vol >= 0.5 && vol <= 2.0) ? clrLime : clrRed;
   ObjectSetString(0, PREFIX+"VVol",  OBJPROP_TEXT, DoubleToString(vol, 2) + "x");
   ObjectSetInteger(0,PREFIX+"VVol",  OBJPROP_COLOR, volColor);

   ObjectSetString(0, PREFIX+"VSMC",  OBJPROP_TEXT, "OB:"+IntegerToString(info.totalActiveOBs)+"/FVG:"+IntegerToString(info.totalActiveFVGs));

   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Eliminar panel                                                    |
//+------------------------------------------------------------------+
void Dashboard::Remove()
  {
   ObjectsDeleteAll(0, PREFIX);
   m_created = false;
  }

//+------------------------------------------------------------------+
//| Funciones auxiliares                                              |
//+------------------------------------------------------------------+
void Dashboard::CreateLabel(string name, int x, int y, string text, color clr, int fontSize, string font)
  {
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Dashboard::CreateBackground(string name, int x, int y, int width, int height, color clr)
  {
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
  }

#endif // __DASHBOARD_MQH__
//+------------------------------------------------------------------+
