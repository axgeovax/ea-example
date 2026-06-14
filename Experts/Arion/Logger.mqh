//+------------------------------------------------------------------+
//|                                                     Logger.mqh   |
//|                        Arion - Logging and Alerts                |
//|                        Autor: Alexy Hernández                    |
//|                        Versión: 1.0                              |
//|        Copyright (c) 2025 Alexy Hernández. Todos los derechos    |
//|        reservados.                                               |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernández. Todos los derechos reservados."
#property link      "https://github.com/axgeovax"
#property version   "1.0"
#property strict

#ifndef __LOGGER_MQH__
#define __LOGGER_MQH__

//+------------------------------------------------------------------+
//| Clase Logger: registro centralizado de operaciones y alertas.    |
//+------------------------------------------------------------------+
class Logger
  {
public:
   //+------------------------------------------------------------------+
   //| Inicializa los canales de salida (CSV, push, email).              |
   //+------------------------------------------------------------------+
   static void       Initialize(string csvFile, bool enablePush, bool enableEmail,
                                string emailDest, string emailSubject);

   //+------------------------------------------------------------------+
   //| Registra una operación (apertura o cierre) en el CSV.             |
   //+------------------------------------------------------------------+
   static void       LogTrade(string symbol, string type, ulong ticket,
                              double price, double volume, double sl, double tp,
                              string comment = "");

   //+------------------------------------------------------------------+
   //| Envía una alerta crítica a todos los canales configurados.        |
   //+------------------------------------------------------------------+
   static void       CriticalAlert(string message);

   //+------------------------------------------------------------------+
   //| Cierra el archivo CSV y libera recursos.                          |
   //+------------------------------------------------------------------+
   static void       Close();

private:
   static string      m_csvFile;
   static bool        m_enablePush;
   static bool        m_enableEmail;
   static string      m_emailDest;
   static string      m_emailSubject;
   static int         m_csvHandle;         // handle del archivo, abierto durante la sesión
  };

// Inicialización de variables estáticas
string Logger::m_csvFile = "";
bool   Logger::m_enablePush = false;
bool   Logger::m_enableEmail = false;
string Logger::m_emailDest = "";
string Logger::m_emailSubject = "";
int    Logger::m_csvHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Inicializar canales de salida                                      |
//+------------------------------------------------------------------+
void Logger::Initialize(string csvFile, bool enablePush, bool enableEmail,
                        string emailDest, string emailSubject)
  {
   m_csvFile = csvFile;
   m_enablePush = enablePush;
   m_enableEmail = enableEmail;
   m_emailDest = emailDest;
   m_emailSubject = emailSubject;

   if(m_csvFile != "")
     {
      m_csvHandle = FileOpen(m_csvFile, FILE_WRITE | FILE_READ | FILE_TXT | FILE_ANSI);
      if(m_csvHandle != INVALID_HANDLE)
        {
         FileSeek(m_csvHandle, 0, SEEK_END);
         if(FileTell(m_csvHandle) == 0)
            FileWrite(m_csvHandle, "Date,Symbol,Type,Ticket,Price,Volume,SL,TP,Comment");
        }
      else
         Print("Logger: could not open ", csvFile, " (error ", GetLastError(), ")");
     }
  }

//+------------------------------------------------------------------+
//| Registrar operación en el CSV y notificar                          |
//+------------------------------------------------------------------+
void Logger::LogTrade(string symbol, string type, ulong ticket,
                      double price, double volume, double sl, double tp,
                      string comment)
  {
   if(m_csvHandle == INVALID_HANDLE)
      return;

   string line = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + "," +
                 symbol + "," + type + "," +
                 IntegerToString(ticket) + "," +
                 DoubleToString(price, 5) + "," +
                 DoubleToString(volume, 2) + "," +
                 DoubleToString(sl, 5) + "," +
                 DoubleToString(tp, 5) + "," +
                 comment;

   FileWrite(m_csvHandle, line);
   FileFlush(m_csvHandle);

   if(m_enablePush)
      SendNotification("Arion: " + type + " " + symbol + " ticket " + IntegerToString(ticket));
   if(m_enableEmail)
      SendMail(m_emailSubject + " - " + type, line);
  }

//+------------------------------------------------------------------+
//| Enviar alerta crítica                                              |
//+------------------------------------------------------------------+
void Logger::CriticalAlert(string message)
  {
   if(m_csvHandle != INVALID_HANDLE)
     {
      string line = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + ",,,ALERT,,,," + message;
      FileWrite(m_csvHandle, line);
      FileFlush(m_csvHandle);
     }

   if(m_enablePush)
      SendNotification("Arion ALERT: " + message);
   if(m_enableEmail)
      SendMail(m_emailSubject + " - ALERT", message);
  }

//+------------------------------------------------------------------+
//| Cerrar archivo y liberar recursos                                  |
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
