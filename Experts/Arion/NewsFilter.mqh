//+------------------------------------------------------------------+
//|                                              NewsFilter.mqh      |
//|                        Arion - Filtro de Noticias                |
//|                        Soporte API + CSV con fallback            |
//|                        Autor: Alexy Hernández                    |
//|                        Versión: 1.0                              |
//|        Copyright (c) 2025 Alexy Hernández. Todos los derechos    |
//|        reservados.                                               |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernández. Todos los derechos reservados."
#property link      "https://github.com/axgeovax"
#property version   "1.0"
#property strict

#ifndef __NEWSFILTER_MQH__
#define __NEWSFILTER_MQH__

//+------------------------------------------------------------------+
//| Estructura de un evento de noticias económicas                    |
//+------------------------------------------------------------------+
struct NewsEvent
  {
   datetime          time;       // fecha y hora del evento
   string            currency;   // código de la moneda (EUR, USD, etc.)
   int               impact;     // 1 = bajo, 2 = medio, 3 = alto
  };

//+------------------------------------------------------------------+
//| Clase NewsFilter: obtiene eventos de API o CSV y determina        |
//| ventanas de silencio alrededor de eventos de alto impacto.        |
//+------------------------------------------------------------------+
class NewsFilter
  {
private:
   NewsEvent         m_events[];            // array de eventos cargados
   int               m_total;               // cantidad actual de eventos
   string            m_csvPath;             // ruta al archivo CSV
   string            m_apiUrl;              // URL de la API de noticias
   int               m_minImpact;           // impacto mínimo a considerar
   int               m_minutesBefore;       // minutos de silencio antes del evento
   int               m_minutesAfter;        // minutos de silencio después del evento
   double            m_spreadFactor;        // multiplicador del spread durante la ventana
   datetime          m_lastLoad;            // última carga exitosa
   bool              m_usingApi;            // true si la última carga fue desde API

   //+------------------------------------------------------------------+
   //| Parsea el archivo CSV y llena el buffer interno de eventos.       |
   //+------------------------------------------------------------------+
   bool              ParseCSV(string path);

   //+------------------------------------------------------------------+
   //| Obtiene eventos desde una API web (JSON) y llena el buffer.      |
   //+------------------------------------------------------------------+
   bool              FetchFromAPI(string url);

public:
   //+------------------------------------------------------------------+
   //| Constructor por defecto.                                           |
   //+------------------------------------------------------------------+
                     NewsFilter();
                    ~NewsFilter() {}

   //+------------------------------------------------------------------+
   //| Configura los parámetros del filtro desde los inputs del EA.       |
   //+------------------------------------------------------------------+
   void              Configure(string csvPath, string apiUrl, int minImpact,
                               int minutesBefore, int minutesAfter, double spreadFactor);

   //+------------------------------------------------------------------+
   //| Carga o recarga el calendario (API preferente, CSV fallback).      |
   //+------------------------------------------------------------------+
   bool              LoadNews();

   //+------------------------------------------------------------------+
   //| Verifica si el símbolo está en periodo de bloqueo.                 |
   //+------------------------------------------------------------------+
   bool              IsLockoutPeriod(string symbolCurrency, double &adjustedSpreadFactor);

   //+------------------------------------------------------------------+
   //| Retorna el spread máximo ajustado por noticias.                    |
   //+------------------------------------------------------------------+
   double            GetMaxSpread(double originalSpread);

   //+------------------------------------------------------------------+
   //| Indica si se está usando la API (true) o el CSV (false).          |
   //+------------------------------------------------------------------+
   bool              IsUsingApi() const { return m_usingApi; }
  };

//+------------------------------------------------------------------+
//| Constructor                                                        |
//+------------------------------------------------------------------+
NewsFilter::NewsFilter()
  {
   m_total = 0;
   m_csvPath = "";
   m_apiUrl = "";
   m_minImpact = 3;
   m_minutesBefore = 15;
   m_minutesAfter = 15;
   m_spreadFactor = 0.5;
   m_lastLoad = 0;
   m_usingApi = false;
  }

//+------------------------------------------------------------------+
//| Configurar parámetros                                             |
//+------------------------------------------------------------------+
void NewsFilter::Configure(string csvPath, string apiUrl, int minImpact,
                           int minutesBefore, int minutesAfter, double spreadFactor)
  {
   m_csvPath = csvPath;
   m_apiUrl = apiUrl;
   m_minImpact = minImpact;
   m_minutesBefore = minutesBefore;
   m_minutesAfter = minutesAfter;
   m_spreadFactor = spreadFactor;
  }

//+------------------------------------------------------------------+
//| Obtener eventos desde API (JSON) – solo si se configura URL       |
//+------------------------------------------------------------------+
bool NewsFilter::FetchFromAPI(string url)
  {
   if(url == "")
      return false;

   char data[];
   char result[];
   string resultHeaders;

   string headers = "Accept: application/json\r\n";
   int timeout = 5000;

   int res = WebRequest("GET", url, headers, timeout, data, result, resultHeaders);
   if(res != 200)
     {
      Print("NewsFilter API: HTTP error ", res);
      return false;
     }

   string json = CharArrayToString(result);
   if(json == "")
      return false;

   ArrayResize(m_events, 0);
   m_total = 0;

// Parseo simple de JSON
   StringReplace(json, "[", "");
   StringReplace(json, "]", "");
   StringReplace(json, "\"", "");

   string records[];
   StringSplit(json, '}', records);

   for(int i = 0; i < ArraySize(records); i++)
     {
      string record = records[i];
      StringTrimLeft(record);
      StringTrimRight(record);
      if(record == "")
         continue;

      string fields[];
      StringSplit(record, ',', fields);
      if(ArraySize(fields) < 3)
         continue;

      datetime time = 0;
      string currency = "";
      int impact = 0;

      for(int j = 0; j < ArraySize(fields); j++)
        {
         string pair[];
         StringSplit(fields[j], ':', pair);
         if(ArraySize(pair) < 2)
            continue;
         StringTrimLeft(pair[0]);
         StringTrimRight(pair[0]);
         StringTrimLeft(pair[1]);
         StringTrimRight(pair[1]);

         if(StringFind(pair[0], "date") >= 0)
            time = StringToTime(pair[1]);
         else
            if(StringFind(pair[0], "currency") >= 0)
               currency = pair[1];
            else
               if(StringFind(pair[0], "impact") >= 0)
                  impact = (int)StringToInteger(pair[1]);
        }

      if(time == 0 || currency == "" || impact < m_minImpact || time < TimeCurrent())
         continue;

      ArrayResize(m_events, m_total + 1);
      m_events[m_total].time     = time;
      m_events[m_total].currency = currency;
      m_events[m_total].impact   = impact;
      m_total++;
     }

   m_lastLoad = TimeCurrent();
   m_usingApi = true;
   Print("NewsFilter API: loaded ", m_total, " future events.");
   return true;
  }

//+------------------------------------------------------------------+
//| Parsear archivo CSV (con respaldo)                                |
//+------------------------------------------------------------------+
bool NewsFilter::ParseCSV(string path)
  {
   string backupPath = path + ".bak";
   int handle = INVALID_HANDLE;

// Intentar principal
   handle = FileOpen(path, FILE_READ | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE || FileSize(handle) <= 0)
     {
      // Cerrar handle si es válido pero archivo vacío
      if(handle != INVALID_HANDLE)
         FileClose(handle);
      // Intentar respaldo
      handle = FileOpen(backupPath, FILE_READ | FILE_TXT | FILE_ANSI);
      if(handle != INVALID_HANDLE && FileSize(handle) > 0)
         Print("NewsFilter CSV: loaded from backup.");
      else
        {
         if(handle != INVALID_HANDLE)
            FileClose(handle);
         Print("NewsFilter CSV: cannot open ", path, " or backup.");
         return false;
        }
     }

   ArrayResize(m_events, 0);
   m_total = 0;

   while(!FileIsEnding(handle))
     {
      string line = FileReadString(handle);
      StringTrimLeft(line);
      StringTrimRight(line);
      if(line == "" || StringFind(line, "#") == 0)
         continue;

      string parts[];
      if(StringSplit(line, ',', parts) < 3)
         continue;

      datetime time = StringToTime(parts[0]);
      string currency = parts[1];
      int impact = (int)StringToInteger(parts[2]);

      if(time == 0 || currency == "" || impact < m_minImpact || time < TimeCurrent())
         continue;

      ArrayResize(m_events, m_total + 1);
      m_events[m_total].time     = time;
      m_events[m_total].currency = currency;
      m_events[m_total].impact   = impact;
      m_total++;
     }

   FileClose(handle);

// Actualizar respaldo (solo si se leyó el principal)
   if(StringFind(path, backupPath) == -1)
      FileCopy(path, 0, backupPath, FILE_REWRITE);

   m_lastLoad = TimeCurrent();
   m_usingApi = false;
   Print("NewsFilter CSV: loaded ", m_total, " future events from ", path);
   return true;
  }

//+------------------------------------------------------------------+
//| Cargar noticias (API preferente, CSV fallback)                    |
//+------------------------------------------------------------------+
bool NewsFilter::LoadNews()
  {
   if(m_total > 0 && TimeCurrent() - m_lastLoad < 1800) // 30 min para API
      return true;

   if(m_apiUrl != "" && FetchFromAPI(m_apiUrl))
      return true;

   if(m_csvPath != "" && ParseCSV(m_csvPath))
      return true;

   return false;
  }

//+------------------------------------------------------------------+
//| Verificar periodo de bloqueo                                      |
//+------------------------------------------------------------------+
bool NewsFilter::IsLockoutPeriod(string symbolCurrency, double &adjustedSpreadFactor)
  {
   if(m_total == 0)
      return false;

   datetime now = TimeCurrent();
   for(int i = 0; i < m_total; i++)
     {
      if(StringFind(symbolCurrency, m_events[i].currency) >= 0)
        {
         datetime start = m_events[i].time - m_minutesBefore * 60;
         datetime end   = m_events[i].time + m_minutesAfter * 60;
         if(now >= start && now <= end)
           {
            adjustedSpreadFactor = m_spreadFactor;
            return true;
           }
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Obtener spread máximo ajustado                                    |
//+------------------------------------------------------------------+
double NewsFilter::GetMaxSpread(double originalSpread)
  {
   double factor = 1.0;
   if(IsLockoutPeriod(_Symbol, factor))
      return originalSpread * factor;
   return originalSpread;
  }

#endif // __NEWSFILTER_MQH__
//+------------------------------------------------------------------+
