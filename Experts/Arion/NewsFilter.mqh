//+------------------------------------------------------------------+
//|                                              NewsFilter.mqh      |
//|                        Arion - Filtro de Noticias                |
//|         Calendario nativo MT5 (prioridad) + API + CSV            |
//|         * CORREGIDO: Impacto real sin inflar, offset horario     |
//|           calculado a partir del servidor (no del PC local).     |
//|                        Autor: Alexy Hernandez                    |
//|                        Version: 1.0                              |
//|        Copyright (c) 2025 Alexy Hernandez. Todos los derechos    |
//|        reservados.                                               |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernandez. Todos los derechos reservados."
#property link      "https://github.com/axgeovax"
#property version   "1.0"
#property strict

#ifndef __NEWSFILTER_MQH__
#define __NEWSFILTER_MQH__

//+------------------------------------------------------------------+
//| Estructura de un evento de noticias economicas                    |
//+------------------------------------------------------------------+
struct NewsEvent
  {
   datetime          time;       // fecha y hora del evento (hora servidor)
   string            currency;   // codigo de la moneda (EUR, USD, etc.)
   int               impact;     // 1 = bajo, 2 = medio, 3 = alto
  };

//+------------------------------------------------------------------+
//| Clase NewsFilter                                                  |
//|                                                                   |
//| Gestiona la carga y consulta de eventos economicos de alto        |
//| impacto para evitar operar durante periodos de volatilidad         |
//| extrema. Soporta tres fuentes en orden de prioridad:              |
//|   1. Calendario nativo de MetaTrader 5 (integrado, sin dependencia|
//|      externa, con correccion de zona horaria del servidor).       |
//|   2. API externa (JSON) con cache de respuesta y parser robusto.  |
//|   3. Archivo CSV local con respaldo automatico.                   |
//|                                                                   |
//| Incorpora throttling inteligente para espaciar las cargas segun   |
//| la proximidad del proximo evento y un sistema de bloqueo por      |
//| ventana de tiempo (minutos antes/despues) que cubre tanto la      |
//| divisa base como la de beneficio del simbolo.                     |
//+------------------------------------------------------------------+
class NewsFilter
  {
private:
   NewsEvent         m_events[];
   int               m_total;
   string            m_csvPath;
   string            m_apiUrl;
   int               m_minImpact;
   int               m_minutesBefore;
   int               m_minutesAfter;
   double            m_spreadFactor;
   datetime          m_lastLoad;
   bool              m_usingApi;

   // Throttling
   datetime          m_nextEventTime;       // hora del evento mas proximo
   datetime          m_lastLoadAttempt;     // ultima vez que se intento cargar
   int               m_throttleInterval;    // intervalo minimo entre cargas (seg)

   // Cache CSV
   datetime          m_csvModTime;          // ultima modificacion del CSV
   // Cache API (respuesta anterior)
   string            m_lastApiResponse;

   bool              ParseCSV(string path);
   bool              FetchFromAPI(string url);
   bool              FetchFromNativeCalendar();
   string            CurrencyFromCountry(string countryCode); // se mantiene por compatibilidad
   string            GetBaseCurrency(string symbol);
   string            GetProfitCurrency(string symbol);

public:
                     NewsFilter();
                    ~NewsFilter() {}

   void              Configure(string csvPath, string apiUrl, int minImpact,
                               int minutesBefore, int minutesAfter, double spreadFactor);
   bool              LoadNews();
   bool              IsLockoutPeriod(string symbolCurrency, double &adjustedSpreadFactor);
   double            GetMaxSpread(double originalSpread);
   bool              IsUsingApi() const { return m_usingApi; }
  };

//+------------------------------------------------------------------+
//| Constructor                                                      |
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
   m_nextEventTime = 0;
   m_lastLoadAttempt = 0;
   m_throttleInterval = 1800;        // 30 min por defecto
   m_csvModTime = 0;
   m_lastApiResponse = "";
  }

//+------------------------------------------------------------------+
//| Configurar parametros                                            |
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
//| Convertir codigo de pais a moneda (mantenida por compatibilidad) |
//+------------------------------------------------------------------+
string NewsFilter::CurrencyFromCountry(string countryCode)
  {
   if(countryCode == "US")
      return "USD";
   if(countryCode == "EU")
      return "EUR";
   if(countryCode == "GB")
      return "GBP";
   if(countryCode == "JP")
      return "JPY";
   if(countryCode == "CH")
      return "CHF";
   if(countryCode == "CA")
      return "CAD";
   if(countryCode == "AU")
      return "AUD";
   if(countryCode == "NZ")
      return "NZD";
   if(countryCode == "CN")
      return "CNY";
   return "";
  }

//+------------------------------------------------------------------+
//| Obtener moneda base del simbolo                                  |
//+------------------------------------------------------------------+
string NewsFilter::GetBaseCurrency(string symbol)
  {
   if(StringLen(symbol) >= 3)
      return StringSubstr(symbol, 0, 3);
   string curr = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
   if(curr != "")
      return curr;
   return "";
  }

//+------------------------------------------------------------------+
//| Obtener moneda de beneficio del simbolo                          |
//+------------------------------------------------------------------+
string NewsFilter::GetProfitCurrency(string symbol)
  {
   string curr = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
   if(curr != "")
      return curr;
// Fallback: extraer de los ultimos 3 caracteres (ej. EURUSD -> USD)
   int len = StringLen(symbol);
   if(len >= 6)
      return StringSubstr(symbol, len-3, 3);
   return "";
  }

//+------------------------------------------------------------------+
//| Obtener eventos desde el calendario nativo MT5 (CORREGIDO)      |
//+------------------------------------------------------------------+
bool NewsFilter::FetchFromNativeCalendar()
  {
   datetime start = TimeCurrent();
   datetime end   = start + 7 * 86400;           // proximos 7 dias
   MqlCalendarValue values[];

   int count = CalendarValueHistory(values, start, end, "", "");
   if(count <= 0)
     {
      Print("NewsFilter Native: No se obtuvieron eventos. Error: ", GetLastError());
      return false;
     }

   ArrayResize(m_events, 0);
   m_total = 0;

// Calcular offset real del servidor (UTC -> hora servidor) usando la hora del broker
   int serverGMTOffset = (int)(TimeCurrent() - TimeGMT());

   for(int i = 0; i < count; i++)
     {
      MqlCalendarEvent event;
      if(!CalendarEventById(values[i].event_id, event))
         continue;

      MqlCalendarCountry country;
      if(!CalendarCountryById(event.country_id, country))
         continue;

      string currency = country.currency;
      if(currency == "")
         continue;

      // Importancia real sin inflar: 1=Bajo, 2=Medio, 3=Alto
      int impact = (int)event.importance;
      if(impact < m_minImpact)
         continue;

      // Convertir a hora del servidor
      datetime eventTime = values[i].time + serverGMTOffset;
      if(eventTime < start)
         continue;

      ArrayResize(m_events, m_total + 1);
      m_events[m_total].time     = eventTime;
      m_events[m_total].currency = currency;
      m_events[m_total].impact   = impact;
      m_total++;
     }

   if(m_total == 0)
     {
      Print("NewsFilter Native: No hay eventos futuros con impacto >= ", m_minImpact);
      m_nextEventTime = 0;
      return false;
     }

// Ordenar eventos por tiempo
   for(int i = 0; i < m_total-1; i++)
      for(int j = i+1; j < m_total; j++)
         if(m_events[i].time > m_events[j].time)
           {
            NewsEvent tmp = m_events[i];
            m_events[i] = m_events[j];
            m_events[j] = tmp;
           }

   m_lastLoad = TimeCurrent();
   m_usingApi = false;
   m_nextEventTime = m_events[0].time;   // evento mas proximo
   Print("NewsFilter Native: Cargados ", m_total, " eventos futuros. Proximo: ", TimeToString(m_nextEventTime));
   return true;
  }

//+------------------------------------------------------------------+
//| Obtener eventos desde API (JSON) – parser robusto                |
//+------------------------------------------------------------------+
bool NewsFilter::FetchFromAPI(string url)
  {
   if(url == "")
      return false;

   char data[], result[];
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

// Cache: si la respuesta es identica a la ultima, no procesar de nuevo
   if(json == m_lastApiResponse && m_total > 0)
     {
      Print("NewsFilter API: respuesta sin cambios, se omite procesamiento.");
      return true; // mantiene eventos anteriores
     }
   m_lastApiResponse = json;

   ArrayResize(m_events, 0);
   m_total = 0;

// --- PARSER JSON ROBUSTO ---
// Buscar cada objeto JSON delimitado por '{' y '}'
   int startPos = 0;
   while(startPos < StringLen(json))
     {
      int openBrace = StringFind(json, "{", startPos);
      if(openBrace == -1)
         break;
      int closeBrace = StringFind(json, "}", openBrace);
      if(closeBrace == -1)
         break;

      string record = StringSubstr(json, openBrace + 1, closeBrace - openBrace - 1);
      startPos = closeBrace + 1;

      // Extraer claves especificas de forma independiente
      string strTime = "";
      string currency = "";
      int impact = 0;

      // Buscar "date": "..." (puede llamarse "date" o "time")
      int keyPos = StringFind(record, "\"date\"");
      if(keyPos == -1)
         keyPos = StringFind(record, "\"time\"");
      if(keyPos != -1)
        {
         int colonPos = StringFind(record, ":", keyPos);
         if(colonPos != -1)
           {
            int firstQuote = StringFind(record, "\"", colonPos);
            if(firstQuote != -1)
              {
               int secondQuote = StringFind(record, "\"", firstQuote + 1);
               if(secondQuote != -1)
                  strTime = StringSubstr(record, firstQuote + 1, secondQuote - firstQuote - 1);
              }
           }
        }

      // Buscar "currency": "..."
      keyPos = StringFind(record, "\"currency\"");
      if(keyPos != -1)
        {
         int colonPos = StringFind(record, ":", keyPos);
         if(colonPos != -1)
           {
            int firstQuote = StringFind(record, "\"", colonPos);
            if(firstQuote != -1)
              {
               int secondQuote = StringFind(record, "\"", firstQuote + 1);
               if(secondQuote != -1)
                  currency = StringSubstr(record, firstQuote + 1, secondQuote - firstQuote - 1);
              }
           }
        }

      // Buscar "impact": numero (puede estar entre comillas o no)
      keyPos = StringFind(record, "\"impact\"");
      if(keyPos != -1)
        {
         int colonPos = StringFind(record, ":", keyPos);
         if(colonPos != -1)
           {
            // Saltar espacios y comillas iniciales
            int valStart = colonPos + 1;
            while(valStart < StringLen(record))
              {
               ushort ch = StringGetCharacter(record, valStart);
               if(ch == ' ' || ch == '\"')
                  valStart++;
               else
                  break;
              }

            string impactStr = "";
            while(valStart < StringLen(record))
              {
               ushort ch = StringGetCharacter(record, valStart);
               if(ch >= '0' && ch <= '9')
                 {
                  impactStr += ShortToString(ch);
                  valStart++;
                 }
               else
                  break;
              }
            impact = (impactStr != "") ? (int)StringToInteger(impactStr) : 0;
           }
        }

      // Validacion de los campos extraidos
      if(strTime == "" || currency == "" || impact < m_minImpact)
         continue;

      datetime eventTime = StringToTime(strTime);
      if(eventTime == 0 || eventTime < TimeCurrent())
         continue;

      ArrayResize(m_events, m_total + 1);
      m_events[m_total].time     = eventTime;
      m_events[m_total].currency = currency;
      m_events[m_total].impact   = impact;
      m_total++;
     }

   m_lastLoad = TimeCurrent();
   m_usingApi = true;
   if(m_total > 0)
      m_nextEventTime = m_events[0].time;
   Print("NewsFilter API: loaded ", m_total, " future events.");
   return true;
  }

//+------------------------------------------------------------------+
//| Parsear archivo CSV con cache por modificacion                   |
//+------------------------------------------------------------------+
bool NewsFilter::ParseCSV(string path)
  {
   if(path == "")
      return false;

// Verificar si el archivo existe y su fecha de modificacion
   datetime modTime = (datetime)FileGetInteger(path, FILE_MODIFY_DATE, false);
   if(modTime != 0 && modTime == m_csvModTime && m_total > 0)
     {
      Print("NewsFilter CSV: archivo sin cambios, se conservan eventos anteriores.");
      return true;
     }
   m_csvModTime = modTime;

   string backupPath = path + ".bak";
   int handle = FileOpen(path, FILE_READ|FILE_TXT|FILE_ANSI);
   if(handle == INVALID_HANDLE || FileSize(handle) <= 0)
     {
      if(handle != INVALID_HANDLE)
         FileClose(handle);
      handle = FileOpen(backupPath, FILE_READ|FILE_TXT|FILE_ANSI);
      if(handle == INVALID_HANDLE || FileSize(handle) <= 0)
        {
         if(handle != INVALID_HANDLE)
            FileClose(handle);
         Print("NewsFilter CSV: cannot open ", path, " or backup.");
         return false;
        }
      Print("NewsFilter CSV: loaded from backup.");
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

   if(StringFind(path, backupPath) == -1)
      FileCopy(path, 0, backupPath, FILE_REWRITE);

   m_lastLoad = TimeCurrent();
   m_usingApi = false;
   if(m_total > 0)
      m_nextEventTime = m_events[0].time;
   Print("NewsFilter CSV: loaded ", m_total, " events from ", path);
   return true;
  }

//+------------------------------------------------------------------+
//| Cargar noticias con throttling inteligente                       |
//+------------------------------------------------------------------+
bool NewsFilter::LoadNews()
  {
   datetime now = TimeCurrent();

// Si ya tenemos eventos y el mas proximo esta a mas de 12 horas, espaciar cargas
   if(m_total > 0 && m_nextEventTime > 0)
     {
      double hoursUntilNext = (double)(m_nextEventTime - now) / 3600.0;
      if(hoursUntilNext > 12.0)
         m_throttleInterval = 7200;   // 2 horas
      else
         if(hoursUntilNext > 6.0)
            m_throttleInterval = 3600;   // 1 hora
         else
            m_throttleInterval = 1800;   // 30 minutos
     }

// Respetar throttling
   if(now - m_lastLoadAttempt < m_throttleInterval && m_total > 0)
      return true;

   m_lastLoadAttempt = now;

// 1. Calendario nativo MT5
   if(FetchFromNativeCalendar())
      return true;

// 2. API externa
   if(m_apiUrl != "" && FetchFromAPI(m_apiUrl))
      return true;

// 3. Archivo CSV
   if(m_csvPath != "" && ParseCSV(m_csvPath))
      return true;

   return false;
  }

//+------------------------------------------------------------------+
//| Verificar periodo de bloqueo (cubre divisas base y profit)       |
//+------------------------------------------------------------------+
bool NewsFilter::IsLockoutPeriod(string symbolCurrency, double &adjustedSpreadFactor)
  {
   if(m_total == 0)
      return false;

// Extraer divisas del simbolo
   string baseCurr = GetBaseCurrency(symbolCurrency);
   string profitCurr = GetProfitCurrency(symbolCurrency);
   if(baseCurr == "")
      baseCurr = symbolCurrency;   // fallback

   datetime now = TimeCurrent();
   for(int i = 0; i < m_total; i++)
     {
      string eventCurr = m_events[i].currency;
      // Verificar coincidencia con divisa base o profit
      if(StringFind(baseCurr, eventCurr) >= 0 || StringFind(eventCurr, baseCurr) >= 0 ||
         (profitCurr != "" && (StringFind(profitCurr, eventCurr) >= 0 || StringFind(eventCurr, profitCurr) >= 0)))
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
//| Obtener spread maximo ajustado                                   |
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
