//+------------------------------------------------------------------+
//|                                                     Logger.mqh   |
//|                        Arion - Logging and Alerts                |
//|                        Autor: Alexy Hernandez                    |
//|                        Version: 1.0                              |
//|        Copyright (c) 2025 Alexy Hernandez. Todos los derechos    |
//|        reservados.                                               |
//|        * CORREGIDO: Registro de cierres (LogClose)               |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernandez. Todos los derechos reservados."
#property link      "https://github.com/axgeovax"
#property version   "1.0"
#property strict

#ifndef __LOGGER_MQH__
#define __LOGGER_MQH__

enum ENUM_LOG_LEVEL
  {
   LOG_DEBUG,
   LOG_INFO,
   LOG_WARNING,
   LOG_ERROR,
   LOG_CRITICAL
  };

//+------------------------------------------------------------------+
//| Clase Logger (estatica)                                          |
//|                                                                   |
//| Proporciona un sistema centralizado de registro de eventos,      |
//| tanto para depuracion como para auditoria. Los mensajes se       |
//| escriben en un archivo CSV con rotacion automatica por tamano.   |
//| Tambien permite enviar notificaciones push y correos electronicos|
//| en operaciones (LogTrade/LogClose) o alertas criticas.           |
//+------------------------------------------------------------------+
class Logger
  {
public:
   static void       Initialize(string csvFile, bool enablePush, bool enableEmail,
                                string emailDest, string emailSubject,
                                int maxSizeMB = 5);
   static void       Log(ENUM_LOG_LEVEL level, string message);
   static void       Debug(string message)   { Log(LOG_DEBUG, message);   }
   static void       Info(string message)    { Log(LOG_INFO, message);    }
   static void       Warning(string message) { Log(LOG_WARNING, message); }
   static void       Error(string message)   { Log(LOG_ERROR, message);   }
   static void       Critical(string message) { Log(LOG_CRITICAL, message);}
   static void       LogTrade(string symbol, string type, ulong ticket,
                              double price, double volume, double sl, double tp,
                              string comment = "");
   static void       LogClose(string symbol, ulong ticket, double closePrice, double profit);
   static void       CriticalAlert(string message);
   static void       Flush();
   static void       Close();

private:
   static string      m_csvFile;
   static bool        m_enablePush;
   static bool        m_enableEmail;
   static string      m_emailDest;
   static string      m_emailSubject;
   static int         m_csvHandle;
   static int         m_maxSizeMB;

   static void        WriteLine(string line);
   static void        CheckRotation();
  };

string Logger::m_csvFile = "";
bool   Logger::m_enablePush = false;
bool   Logger::m_enableEmail = false;
string Logger::m_emailDest = "";
string Logger::m_emailSubject = "";
int    Logger::m_csvHandle = INVALID_HANDLE;
int    Logger::m_maxSizeMB = 5;

//+------------------------------------------------------------------+
//| Inicializa el sistema de logging.                                |
//+------------------------------------------------------------------+
void Logger::Initialize(string csvFile, bool enablePush, bool enableEmail,
                        string emailDest, string emailSubject,
                        int maxSizeMB = 5)
  {
   m_csvFile = csvFile;
   m_enablePush = enablePush;
   m_enableEmail = enableEmail;
   m_emailDest = emailDest;
   m_emailSubject = emailSubject;
   m_maxSizeMB = MathMax(1, maxSizeMB);

   if(m_csvFile != "")
     {
      // Asegurar que la carpeta existe
      string folder = m_csvFile;
      int pos = StringFind(folder, "\\", 0);
      while(pos >= 0)
        {
         FolderCreate(StringSubstr(folder, 0, pos));
         pos = StringFind(folder, "\\", pos + 1);
        }

      m_csvHandle = FileOpen(m_csvFile, FILE_WRITE | FILE_READ | FILE_TXT | FILE_ANSI);
      if(m_csvHandle != INVALID_HANDLE)
        {
         FileSeek(m_csvHandle, 0, SEEK_END);
         if(FileTell(m_csvHandle) == 0)
            FileWrite(m_csvHandle, "Timestamp,Level,Symbol,Type,Ticket,Price,Volume,SL,TP,Comment");
        }
      else
         Print("Logger: could not open ", csvFile, " (error ", GetLastError(), ")");
     }
  }

//+------------------------------------------------------------------+
//| Verifica si el archivo de log actual supera el tamano maximo     |
//| y lo rota si es necesario.                                        |
//+------------------------------------------------------------------+
void Logger::CheckRotation()
  {
   if(m_csvHandle == INVALID_HANDLE)
      return;

   FileFlush(m_csvHandle);

   ulong maxSizeBytes = (ulong)m_maxSizeMB * 1024 * 1024;
   if(FileTell(m_csvHandle) > maxSizeBytes)
     {
      FileClose(m_csvHandle);
      m_csvHandle = INVALID_HANDLE;

      string timestamp = TimeToString(TimeCurrent(), TIME_DATE);
      StringReplace(timestamp, ".", "-");
      string rotatedName = m_csvFile + "." + timestamp + ".bak";
      if(!FileMove(m_csvFile, 0, rotatedName, 0))
         Print("Logger: could not rotate log to ", rotatedName);

      m_csvHandle = FileOpen(m_csvFile, FILE_WRITE | FILE_TXT | FILE_ANSI);
      if(m_csvHandle != INVALID_HANDLE)
         FileWrite(m_csvHandle, "Timestamp,Level,Symbol,Type,Ticket,Price,Volume,SL,TP,Comment");
      else
         Print("Logger: could not reopen log after rotation");
     }
  }

//+------------------------------------------------------------------+
//| Escribe una linea en el archivo de log.                          |
//+------------------------------------------------------------------+
void Logger::WriteLine(string line)
  {
   if(m_csvFile == "")
      return;
   if(m_csvHandle == INVALID_HANDLE)
     {
      m_csvHandle = FileOpen(m_csvFile, FILE_WRITE | FILE_READ | FILE_TXT | FILE_ANSI);
      if(m_csvHandle == INVALID_HANDLE)
         return;
     }

   CheckRotation();
   if(m_csvHandle != INVALID_HANDLE)
     {
      FileWrite(m_csvHandle, line);
      FileFlush(m_csvHandle);
     }
  }

//+------------------------------------------------------------------+
//| Registra un mensaje generico con el nivel de severidad indicado. |
//+------------------------------------------------------------------+
void Logger::Log(ENUM_LOG_LEVEL level, string message)
  {
   string levelStr;
   switch(level)
     {
      case LOG_DEBUG:
         levelStr = "DEBUG";
         break;
      case LOG_INFO:
         levelStr = "INFO";
         break;
      case LOG_WARNING:
         levelStr = "WARNING";
         break;
      case LOG_ERROR:
         levelStr = "ERROR";
         break;
      case LOG_CRITICAL:
         levelStr = "CRITICAL";
         break;
      default:
         levelStr = "UNKNOWN";
         break;
     }

   string line = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + "," +
                 levelStr + ",,,," + message;

   WriteLine(line);
  }

//+------------------------------------------------------------------+
//| Registra una operacion de trading con todos sus detalles.        |
//+------------------------------------------------------------------+
void Logger::LogTrade(string symbol, string type, ulong ticket,
                      double price, double volume, double sl, double tp,
                      string comment)
  {
   string line = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + "," +
                 "INFO," + symbol + "," + type + "," +
                 IntegerToString(ticket) + "," +
                 DoubleToString(price, 5) + "," +
                 DoubleToString(volume, 2) + "," +
                 DoubleToString(sl, 5) + "," +
                 DoubleToString(tp, 5) + "," +
                 comment;

   WriteLine(line);

   if(m_enablePush)
      SendNotification("Arion: " + type + " " + symbol + " ticket " + IntegerToString(ticket));
   if(m_enableEmail)
      SendMail(m_emailSubject + " - " + type, line);
  }

//+------------------------------------------------------------------+
//| Registra el cierre de una operacion con precio de salida y P&L.  |
//+------------------------------------------------------------------+
void Logger::LogClose(string symbol, ulong ticket, double closePrice, double profit)
  {
   string line = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + "," +
                 "INFO," + symbol + ",CLOSE," + IntegerToString(ticket) + "," +
                 DoubleToString(closePrice, 5) + ",," +
                 DoubleToString(profit, 2) + ",,";

   WriteLine(line);

   if(m_enablePush)
      SendNotification("Arion: CLOSE " + symbol + " ticket " + IntegerToString(ticket) + " P&L=" + DoubleToString(profit, 2));
   if(m_enableEmail)
      SendMail(m_emailSubject + " - CLOSE", line);
  }

//+------------------------------------------------------------------+
//| Envia una alerta critica.                                        |
//+------------------------------------------------------------------+
void Logger::CriticalAlert(string message)
  {
   Log(LOG_CRITICAL, message);

   if(m_enablePush)
      SendNotification("Arion ALERT: " + message);
   if(m_enableEmail)
      SendMail(m_emailSubject + " - ALERT", message);
  }

//+------------------------------------------------------------------+
//| Fuerza el volcado de los datos pendientes al archivo de log.     |
//+------------------------------------------------------------------+
void Logger::Flush()
  {
   if(m_csvHandle != INVALID_HANDLE)
      FileFlush(m_csvHandle);
  }

//+------------------------------------------------------------------+
//| Cierra el archivo de log y libera el recurso.                    |
//+------------------------------------------------------------------+
void Logger::Close()
  {
   if(m_csvHandle != INVALID_HANDLE)
     {
      FileClose(m_csvHandle);
      m_csvHandle = INVALID_HANDLE;
     }
  }

#endif // __LOGGER_MQH__
//+------------------------------------------------------------------+
