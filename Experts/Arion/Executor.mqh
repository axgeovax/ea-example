//+------------------------------------------------------------------+
//|                                                  Executor.mqh    |
//|                        Arion - Ejecución Asíncrona Avanzada      |
//|   Llenado adaptativo, Slippage dinámico, Margen variable,        |
//|   BE/Trailing por pips, Back‑off selectivo                       |
//|                        Autor: Alexy Hernández                    |
//|                        Versión: 1.0                              |
//|        Copyright (c) 2025 Alexy Hernández. Todos los derechos    |
//|        reservados.                                               |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernández. Todos los derechos reservados."
#property link      "https://github.com/axgeovax"
#property version   "1.0"
#property strict

#include <Trade\Trade.mqh>

#ifndef __EXECUTOR_MQH__
#define __EXECUTOR_MQH__

//+------------------------------------------------------------------+
//| Estados posibles de una orden asíncrona                           |
//+------------------------------------------------------------------+
enum ENUM_ARION_ORDER_STATE
  {
   ARION_ORDER_STATE_NONE,
   ARION_ORDER_STATE_PENDING,
   ARION_ORDER_STATE_FILLED,
   ARION_ORDER_STATE_ERROR
  };

//+------------------------------------------------------------------+
//| Clase Executor: gestión avanzada de órdenes                       |
//+------------------------------------------------------------------+
class Executor
  {
private:
   string                  m_symbol;
   int                     m_maxRetries;
   long                    m_magicNumber;
   string                  m_blockedAssets[];
   datetime                m_blockTime[];
   int                     m_totalBlocked;
   CTrade                  m_trade;
   ENUM_ARION_ORDER_STATE  m_orderState;
   int                     m_currentRetries;
   bool                    m_orderInFlight;
   datetime                m_sendTime;
   datetime                m_lastBECheck;
   datetime                m_lastTrailCheck;

   int                     m_asyncTimeout;
   int                     m_consecutiveTimeouts;

   // --- Variables para BE y Trailing adaptativo ---
   double                  m_lastBEPrice;       // precio al último BE
   double                  m_lastTrailPrice;    // precio al último ajuste trailing
   double                  m_trailStepPips;     // paso mínimo (se adapta)
   double                  m_trailDistancePips; // distancia base (se adapta)

   // --- Indicador ATR M1 para slippage dinámico y margen ---
   int                     m_handleATR_M1;

   //+------------------------------------------------------------------+
   //| Obtiene el precio actual (Ask o Bid) según el tipo de orden.       |
   //+------------------------------------------------------------------+
   double                  GetUpdatedPrice(ENUM_ORDER_TYPE type);

   //+------------------------------------------------------------------+
   //| Verifica si el símbolo está temporalmente bloqueado.               |
   //+------------------------------------------------------------------+
   bool                    IsBlocked();

   //+------------------------------------------------------------------+
   //| Bloquea el símbolo durante una cantidad de segundos.               |
   //+------------------------------------------------------------------+
   void                    BlockAsset(int seconds = 60);

   //+------------------------------------------------------------------+
   //| Calcula el slippage dinámico en puntos (ATR M1).                   |
   //+------------------------------------------------------------------+
   int                     CalculateDynamicSlippage();

   //+------------------------------------------------------------------+
   //| Safety margin factor: entre 1.2 y 2.0 según exposición/volatilidad|
   //+------------------------------------------------------------------+
   double                  GetSafetyMarginFactor();

   //+------------------------------------------------------------------+
   //| Obtiene el ATR M1 actual del símbolo                               |
   //+------------------------------------------------------------------+
   double                  GetATR_M1();

   //+------------------------------------------------------------------+
   //| Lógica de alternancia de filling para reintentos                   |
   //+------------------------------------------------------------------+
   ENUM_ORDER_TYPE_FILLING GetFillingMode();

public:
                     Executor(string symbol = NULL, long magicBase = 202400);
                    ~Executor();

   bool                    Initialize();
   bool                    SendMarketOrder(ENUM_ORDER_TYPE type, double lot, double sl, double tp, string comment = "");
   void                    ProcessTransaction(const MqlTradeTransaction& trans,
         const MqlTradeRequest& request,
         const MqlTradeResult& result);
   void                    ManageBreakeven(double activationRatio = 1.0, double extraPoints = 5.0);
   void                    ManageTrailingStop(double trailStartRatio = 1.5,
         double trailDistancePips = 50.0,
         double trailStepPips = 5.0);
   void                    ClearLocks();
   void                    SetAsyncTimeout(int seconds) { m_asyncTimeout = (seconds > 0) ? seconds : 30; }
   string                  GetSymbol() const { return m_symbol; }
   ENUM_ARION_ORDER_STATE  GetState() const { return m_orderState; }
   bool                    HasOrderInFlight() const { return m_orderInFlight; }
  };

//+------------------------------------------------------------------+
//| Constructor                                                        |
//+------------------------------------------------------------------+
Executor::Executor(string symbol, long magicBase)
  {
   m_symbol = (symbol == NULL) ? _Symbol : symbol;
   m_maxRetries = 3;
   m_magicNumber = magicBase;
   m_totalBlocked = 0;
   ArrayResize(m_blockedAssets, 0);
   ArrayResize(m_blockTime, 0);
   m_orderState = ARION_ORDER_STATE_NONE;
   m_currentRetries = 0;
   m_orderInFlight = false;
   m_sendTime = 0;
   m_lastBECheck = 0;
   m_lastTrailCheck = 0;
   m_asyncTimeout = 30;
   m_consecutiveTimeouts = 0;
   m_lastBEPrice = 0;
   m_lastTrailPrice = 0;
   m_trailStepPips = 5.0;
   m_trailDistancePips = 50.0;
   m_handleATR_M1 = INVALID_HANDLE;
  }

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
Executor::~Executor()
  {
   if(m_handleATR_M1 != INVALID_HANDLE)
      IndicatorRelease(m_handleATR_M1);
  }

//+------------------------------------------------------------------+
//| Inicializar                                                        |
//+------------------------------------------------------------------+
bool Executor::Initialize()
  {
   if(!SymbolSelect(m_symbol, true))
     {
      Print("Error [Executor]: Symbol ", m_symbol, " not available.");
      return false;
     }
   m_handleATR_M1 = iATR(m_symbol, PERIOD_M1, 14);
   return true;
  }

//+------------------------------------------------------------------+
//| Obtener precio actualizado                                         |
//+------------------------------------------------------------------+
double Executor::GetUpdatedPrice(ENUM_ORDER_TYPE type)
  {
   return (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(m_symbol, SYMBOL_ASK)
          : SymbolInfoDouble(m_symbol, SYMBOL_BID);
  }

//+------------------------------------------------------------------+
//| Verificar bloqueo                                                  |
//+------------------------------------------------------------------+
bool Executor::IsBlocked()
  {
   for(int i = 0; i < m_totalBlocked; i++)
     {
      if(m_blockedAssets[i] == m_symbol)
        {
         if(TimeCurrent() < m_blockTime[i])
            return true;
         // Eliminar bloqueo expirado
         for(int j = i; j < m_totalBlocked - 1; j++)
           {
            m_blockedAssets[j] = m_blockedAssets[j+1];
            m_blockTime[j] = m_blockTime[j+1];
           }
         m_totalBlocked--;
         ArrayResize(m_blockedAssets, m_totalBlocked);
         ArrayResize(m_blockTime, m_totalBlocked);
         return false;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Bloquear activo                                                    |
//+------------------------------------------------------------------+
void Executor::BlockAsset(int seconds)
  {
   if(IsBlocked())
      return;
   ArrayResize(m_blockedAssets, m_totalBlocked + 1);
   ArrayResize(m_blockTime, m_totalBlocked + 1);
   m_blockedAssets[m_totalBlocked] = m_symbol;
   m_blockTime[m_totalBlocked] = TimeCurrent() + seconds;
   m_totalBlocked++;
   Print("⚠ [Executor] Asset ", m_symbol, " blocked for ", seconds, " seconds.");
  }

//+------------------------------------------------------------------+
//| Liberar bloqueos y timeouts (back‑off progresivo)                  |
//+------------------------------------------------------------------+
void Executor::ClearLocks()
  {
   for(int i = m_totalBlocked - 1; i >= 0; i--)
     {
      if(TimeCurrent() >= m_blockTime[i])
        {
         for(int j = i; j < m_totalBlocked - 1; j++)
           {
            m_blockedAssets[j] = m_blockedAssets[j+1];
            m_blockTime[j] = m_blockTime[j+1];
           }
         m_totalBlocked--;
        }
     }
   ArrayResize(m_blockedAssets, m_totalBlocked);
   ArrayResize(m_blockTime, m_totalBlocked);

   if(m_orderInFlight && m_sendTime > 0 && TimeCurrent() - m_sendTime > m_asyncTimeout)
     {
      m_consecutiveTimeouts++;
      Print("⚠ [Executor] Async order timeout #", m_consecutiveTimeouts, " for ", m_symbol);
      m_orderInFlight = false;
      m_orderState = ARION_ORDER_STATE_ERROR;
      m_currentRetries = 0;
      // Bloqueo exponencial: 60 * 2^(timeouts-1), máx 5 min
      int seconds = 60 * MathMin(1 << MathMin(m_consecutiveTimeouts-1, 3), 5);
      BlockAsset(seconds);
     }
  }

//+------------------------------------------------------------------+
//| Calcular slippage dinámico basado en ATR M1                        |
//+------------------------------------------------------------------+
int Executor::CalculateDynamicSlippage()
  {
   double atr = GetATR_M1();
   if(atr <= 0)
      return 30; // fallback

   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   if(point <= 0)
      return 30;

// Slippage = 30% del ATR en puntos, pero mínimo 10 y máximo 100
   int slip = (int)(0.3 * atr / point);
   if(slip < 10)
      slip = 10;
   if(slip > 100)
      slip = 100;
   return slip;
  }

//+------------------------------------------------------------------+
//| Obtener ATR M1 actual                                             |
//+------------------------------------------------------------------+
double Executor::GetATR_M1()
  {
   if(m_handleATR_M1 == INVALID_HANDLE)
      m_handleATR_M1 = iATR(m_symbol, PERIOD_M1, 14);

   if(m_handleATR_M1 != INVALID_HANDLE)
     {
      double buf[1];
      if(CopyBuffer(m_handleATR_M1, 0, 0, 1, buf) == 1)
         return buf[0];
     }
   return 0.0;
  }

//+------------------------------------------------------------------+
//| Safety margin factor adaptativo                                    |
//+------------------------------------------------------------------+
double Executor::GetSafetyMarginFactor()
  {
   double base = 1.2;

// A mayor volatilidad, más margen requerido
   double atr = GetATR_M1();
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   if(atr > 0 && point > 0)
     {
      int atrPoints = (int)(atr / point);
      if(atrPoints > 50)
         base += 0.3;
      else
         if(atrPoints > 20)
            base += 0.2;
     }

// Exposición: si hay más de 5 posiciones totales, incrementar
   if(PositionsTotal() > 5)
      base += 0.2;

// Margen libre disponible: si es menos del 200% del margen requerido, aumentar
   double marginFree = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double marginUsed = AccountInfoDouble(ACCOUNT_MARGIN);
   if(marginFree > 0 && marginUsed > 0 && marginFree < marginUsed * 2)
      base += 0.3;

   return MathMin(base, 2.5);
  }

//+------------------------------------------------------------------+
//| Modo de llenado según el número de reintento                       |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING Executor::GetFillingMode()
  {
// Alternar: primer intento FOK, luego IOC, luego RETURN
   if(m_currentRetries == 0)
      return ORDER_FILLING_FOK;
   else
      if(m_currentRetries == 1)
         return ORDER_FILLING_IOC;
      else
         return ORDER_FILLING_RETURN;
  }

//+------------------------------------------------------------------+
//| Enviar orden de mercado asíncrona                                  |
//+------------------------------------------------------------------+
bool Executor::SendMarketOrder(ENUM_ORDER_TYPE type, double lot,
                               double sl, double tp, string comment)
  {
   if(IsBlocked())
     {
      Print("Error [Executor]: ", m_symbol, " is blocked.");
      return false;
     }
   if(lot <= 0.0)
      return false;
   if(m_orderInFlight)
     {
      Print("Error [Executor]: An order is already in flight for ", m_symbol);
      return false;
     }

// Verificar margen con factor adaptativo
   double marginFree = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double marginReq = 0.0;
   double price = GetUpdatedPrice(type);
   if(price <= 0.0)
      return false;
   if(!OrderCalcMargin(type, m_symbol, lot, price, marginReq))
     {
      Print("Error [Executor]: Could not calculate margin.");
      return false;
     }

   double safetyFactor = GetSafetyMarginFactor();
   if(marginFree < marginReq * safetyFactor)
     {
      Print("Error [Executor]: Insufficient margin (Free=", marginFree, " Required=", marginReq, " SafetyFactor=", safetyFactor, ")");
      BlockAsset(300);
      return false;
     }

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = m_symbol;
   request.volume    = lot;
   request.type      = type;
   request.deviation = CalculateDynamicSlippage();  // slippage dinámico
   request.magic     = m_magicNumber;
   request.comment   = comment;
   request.type_filling = GetFillingMode();        // llenado adaptativo
   request.price     = price;

   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   if(type == ORDER_TYPE_BUY)
     {
      request.sl = (sl > 0) ? price - sl * point : 0;
      request.tp = (tp > 0) ? price + tp * point : 0;
     }
   else
     {
      request.sl = (sl > 0) ? price + sl * point : 0;
      request.tp = (tp > 0) ? price - tp * point : 0;
     }

   if(!OrderSendAsync(request, result))
     {
      Print("Error [Executor]: OrderSendAsync failed immediately. Retcode: ", result.retcode);
      return false;
     }

   m_orderInFlight = true;
   m_orderState = ARION_ORDER_STATE_PENDING;
   m_currentRetries = 0;
   m_sendTime = TimeCurrent();
   return true;
  }

//+------------------------------------------------------------------+
//| Procesar respuesta del bróker (back‑off selectivo)                 |
//+------------------------------------------------------------------+
void Executor::ProcessTransaction(const MqlTradeTransaction& trans,
                                  const MqlTradeRequest& request,
                                  const MqlTradeResult& result)
  {
   if(!m_orderInFlight)
      return;
   if(request.symbol != m_symbol || request.magic != m_magicNumber)
      return;

   switch(result.retcode)
     {
      // --- Éxito ---
      case TRADE_RETCODE_DONE:
      case TRADE_RETCODE_DONE_PARTIAL:
         m_orderInFlight = false;
         m_orderState = ARION_ORDER_STATE_FILLED;
         m_consecutiveTimeouts = 0;
         Print("✅ Async order executed on ", m_symbol, " ticket ", result.order);
         break;

      // --- Reintento inmediato (ajustar precio y filling) ---
      case TRADE_RETCODE_REQUOTE:
      case TRADE_RETCODE_PRICE_CHANGED:
      case TRADE_RETCODE_PRICE_OFF:
         if(++m_currentRetries >= m_maxRetries)
           {
            m_orderInFlight = false;
            m_orderState = ARION_ORDER_STATE_ERROR;
            BlockAsset(60);
           }
         else
           {
            double newPrice = GetUpdatedPrice((ENUM_ORDER_TYPE)request.type);
            if(newPrice > 0.0)
              {
               MqlTradeRequest newReq = request;
               MqlTradeResult  newRes;
               newReq.price = newPrice;
               newReq.deviation = CalculateDynamicSlippage();
               newReq.type_filling = GetFillingMode(); // alternar filling
               if(OrderSendAsync(newReq, newRes))
                 {
                  m_sendTime = TimeCurrent();
                 }
               else
                 {
                  m_orderInFlight = false;
                  m_orderState = ARION_ORDER_STATE_ERROR;
                  BlockAsset(60);
                 }
              }
           }
         break;

      // --- Errores temporales (servidor) ---
      case TRADE_RETCODE_TIMEOUT:
      case TRADE_RETCODE_CONNECTION:
         if(++m_currentRetries < m_maxRetries)
           {
            Sleep(200);
            MqlTradeRequest newReq = request;
            MqlTradeResult  newRes;
            newReq.deviation = CalculateDynamicSlippage();
            newReq.type_filling = GetFillingMode();
            if(OrderSendAsync(newReq, newRes))
               m_sendTime = TimeCurrent();
            else
              {
               m_orderInFlight = false;
               m_orderState = ARION_ORDER_STATE_ERROR;
              }
           }
         else
           {
            m_orderInFlight = false;
            m_orderState = ARION_ORDER_STATE_ERROR;
            BlockAsset(60);
           }
         break;

      // --- Errores fatales: bloqueo largo exponencial ---
      case TRADE_RETCODE_MARKET_CLOSED:
      case TRADE_RETCODE_TRADE_DISABLED:
      case TRADE_RETCODE_FROZEN:
      case TRADE_RETCODE_INVALID_FILL:
      case TRADE_RETCODE_LIMIT_VOLUME:
      case TRADE_RETCODE_NO_MONEY:
         m_orderInFlight = false;
         m_orderState = ARION_ORDER_STATE_ERROR;
           {
            int seconds = 60 * MathMin(1 << MathMin(m_consecutiveTimeouts, 3), 5);
            BlockAsset(seconds);
           }
         break;

      // --- Stops inválidos ---
      case TRADE_RETCODE_INVALID_STOPS:
         m_orderInFlight = false;
         m_orderState = ARION_ORDER_STATE_ERROR;
         Print("Error [Executor] Invalid stops on ", m_symbol, ". Check SL/TP.");
         BlockAsset(120);
         break;

      // --- Otros: error genérico ---
      default:
         if(++m_currentRetries >= m_maxRetries)
           {
            m_orderInFlight = false;
            m_orderState = ARION_ORDER_STATE_ERROR;
            BlockAsset(60);
           }
         break;
     }
  }

//+------------------------------------------------------------------+
//| Gestionar breakeven (basado en pips de movimiento)                 |
//+------------------------------------------------------------------+
void Executor::ManageBreakeven(double activationRatio, double extraPoints)
  {
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
   long stopLevel = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);

   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != m_symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != m_magicNumber)
         continue;

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice  = PositionGetDouble(POSITION_PRICE_OPEN);
      double originalSL = PositionGetDouble(POSITION_SL);
      double originalTP = PositionGetDouble(POSITION_TP);
      if(originalSL == 0)
         continue;

      double currentPrice = (posType == POSITION_TYPE_BUY) ? bid : ask;
      double slDist = (posType == POSITION_TYPE_BUY) ? (openPrice - originalSL) / point
                      : (originalSL - openPrice) / point;
      if(slDist <= 0)
         continue;

      double profitPips = (posType == POSITION_TYPE_BUY) ? (currentPrice - openPrice) / point
                          : (openPrice - currentPrice) / point;

      // Verificar si ya hemos aplicado BE para este ticket
      if(m_lastBEPrice != 0 && MathAbs(currentPrice - m_lastBEPrice) < point * InpMinPipsDisplacement)
         continue; // no ha habido suficiente movimiento

      if(profitPips >= slDist * activationRatio)
        {
         double newSL;
         if(posType == POSITION_TYPE_BUY)
            newSL = openPrice + extraPoints * point;
         else
            newSL = openPrice - extraPoints * point;

         if((posType == POSITION_TYPE_BUY && newSL <= originalSL) ||
            (posType == POSITION_TYPE_SELL && newSL >= originalSL))
            continue;

         double distanceToPrice = MathAbs(currentPrice - newSL) / point;
         if(distanceToPrice < stopLevel)
            continue;

         if((posType == POSITION_TYPE_BUY && newSL >= currentPrice) ||
            (posType == POSITION_TYPE_SELL && newSL <= currentPrice))
            continue;

         if(PositionSelectByTicket(ticket))
           {
            if(m_trade.PositionModify(ticket, newSL, originalTP))
              {
               Print("✔ Breakeven applied on ", m_symbol, " ticket ", ticket);
               m_lastBEPrice = currentPrice;
              }
            else
               Print("Error [Executor] modifying SL to BE: ", GetLastError());
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Gestionar trailing stop dinámico (adaptativo por momentum)        |
//+------------------------------------------------------------------+
void Executor::ManageTrailingStop(double trailStartRatio, double trailDistancePips, double trailStepPips)
  {
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
   long stopLevel = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);

   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != m_symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != m_magicNumber)
         continue;

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice  = PositionGetDouble(POSITION_PRICE_OPEN);
      double originalSL = PositionGetDouble(POSITION_SL);
      double originalTP = PositionGetDouble(POSITION_TP);
      if(originalSL == 0)
         continue;

      double currentPrice = (posType == POSITION_TYPE_BUY) ? bid : ask;

      // Ganancia en pips
      double profitPips = (posType == POSITION_TYPE_BUY) ? (currentPrice - openPrice) / point
                          : (openPrice - currentPrice) / point;
      if(profitPips <= 0)
         continue;

      // SL inicial en pips
      double slDist = (posType == POSITION_TYPE_BUY) ? (openPrice - originalSL) / point
                      : (originalSL - openPrice) / point;

      // Ajustar distancia y paso según momentum
      double momentum = 0.0;
      // Calculamos momentum simple con 5 barras M1
      double closeArr[];
      if(CopyClose(m_symbol, PERIOD_M1, 5, 1, closeArr) == 1)
         momentum = (currentPrice - closeArr[0]) / point;

      double dynamicTrailDist = trailDistancePips;
      double dynamicTrailStep = trailStepPips;

      if(momentum > 20)           // movimiento fuerte a favor
        {
         dynamicTrailDist = trailDistancePips * 0.7;
         dynamicTrailStep = trailStepPips * 0.5;
        }
      else
         if(momentum > 10)
           {
            dynamicTrailDist = trailDistancePips * 0.9;
            dynamicTrailStep = trailStepPips * 0.8;
           }
      // si momentum es bajo, dejamos valores base

      // Solo activar si la ganancia supera el ratio de inicio
      if(profitPips < slDist * trailStartRatio)
         continue;

      double newSL;
      if(posType == POSITION_TYPE_BUY)
         newSL = currentPrice - dynamicTrailDist * point;
      else
         newSL = currentPrice + dynamicTrailDist * point;

      // Mejorar SL solo si el nuevo es mejor que el actual
      if((posType == POSITION_TYPE_BUY && newSL <= originalSL) ||
         (posType == POSITION_TYPE_SELL && newSL >= originalSL))
         continue;

      // Verificar movimiento mínimo para ajustar (paso adaptativo)
      if(m_lastTrailPrice != 0)
        {
         double moveSinceLast = MathAbs(currentPrice - m_lastTrailPrice) / point;
         if(moveSinceLast < dynamicTrailStep)
            continue;
        }

      // Verificar stop level y lado correcto
      double distanceToPrice = MathAbs(currentPrice - newSL) / point;
      if(distanceToPrice < stopLevel)
         continue;

      if((posType == POSITION_TYPE_BUY && newSL >= currentPrice) ||
         (posType == POSITION_TYPE_SELL && newSL <= currentPrice))
         continue;

      if(PositionSelectByTicket(ticket))
        {
         if(m_trade.PositionModify(ticket, newSL, originalTP))
           {
            Print("✔ Trailing SL updated on ", m_symbol, " ticket ", ticket, " SL=", DoubleToString(newSL, 5));
            m_lastTrailPrice = currentPrice;
           }
         else
            Print("Error [Executor] modifying SL to trailing: ", GetLastError());
        }
     }
  }

#endif // __EXECUTOR_MQH__
//+------------------------------------------------------------------+
