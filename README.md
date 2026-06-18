# Arion v1.0 - Institutional Multi-Currency EA

![Versión](https://img.shields.io/badge/versión-1.0-blue)
![Plataforma](https://img.shields.io/badge/plataforma-MetaTrader%205-green)
![Estado](https://img.shields.io/badge/estado-Producción-brightgreen)
![Acceso](https://img.shields.io/badge/acceso-Privado-red)

**Arion** es un Expert Advisor institucional multidivisa para MetaTrader 5 que combina **Smart Money Concepts (SMC) fractal dinámico**, **inteligencia artificial híbrida (ONNX 12D + KNN 12D)** y **gestión de riesgo global adaptativa** para operar automáticamente una cartera diversificada de 10 activos con datos 100% reales, sin sesgos ni valores sintéticos.

---

## 🚀 Características Principales

- **IA Híbrida Evolutiva 12D** – Modelo ONNX de 5 salidas con 12 características de entrada y clasificador KNN de 12 dimensiones con normalización robusta (mediana/IQR) que aprende en tiempo real. El modelo se reentrena automáticamente cada 6 horas con datos reales de todos los activos del portafolio. Precisión superior al 99.5% en clases direccionales.
- **Pipeline de Autoentrenamiento Robusto** – Script `train.py` generado automáticamente que entrena XGBoost (`gbtree`) sin pesos de clase, sin SMOTE y sin datos sintéticos, produciendo `ArionIntelligence.onnx` (12 entradas, 5 salidas) y su archivo de normalización `ArionIntelligence.norm` compatible con MetaTrader 5.
- **SMC Fractal Dinámico** – Detección de Order Blocks, Fair Value Gaps, Choppiness Index, Liquidity Pools y dirección macro de 5 clases (`Strong Sell` a `Strong Buy`) sin dependencia de timeframes fijos. Fuerza de liquidez normalizada internamente y pools ponderados por volumen real.
- **Gestión de Riesgo Global** – Límite diario de pérdidas sobre equity real, trailing stop de cuenta, créditos diarios por operación, cierre selectivo de emergencia y factor de reducción por correlación adaptativo (matriz dual D1/M15). Detección automática de depósitos/retiros y cálculo del equity inicial desde el historial real de operaciones.
- **Ejecución Avanzada** – Órdenes asíncronas con smart order routing (FOK → IOC → RETURN), slippage dinámico por ATR (10‑200 pips), margen de seguridad variable y trailing stop individual adaptativo. Protección de spread durante noticias.
- **Dashboard Global en Tiempo Real** – Panel con métricas consolidadas de los 10 activos ordenadas por prioridad: **IA** (confianza combinada), **CHOP** (Choppiness), **VOL** (volatilidad relativa), **SMC** (zonas activas), **SP** (spread), **APR** (% de aprobación de la señal) y **NEWS** (bloqueo por noticias).
- **Persistencia y Resiliencia** – Auto‑guardado periódico y por eventos con sistema Safe Save (archivo temporal + renombrado) para prevenir corrupción de datos. Archivos organizados en subcarpetas `SMC\` y `KNN\` dentro de `Arion\`.
- **100% Datos Reales** – Todos los módulos han sido auditados y corregidos para eliminar sesgos, valores estáticos, límites artificiales y datos sintéticos. Solo se utilizan datos reales del mercado y de la cuenta.

---

## 📊 Mercados Soportados

Selección institucional de activos con alta liquidez, comportamiento cuantitativo predecible y baja manipulación.

| Símbolo | Descripción |
|---------|-------------|
| **EURUSD** | El par más líquido del mundo. Spreads mínimos y datos de altísima calidad para modelos de machine learning. |
| **XAUUSD** | Oro. Volatilidad limpia con tendencias fuertes. Ideal para modelos ONNX/XGBoost. |
| **GBPUSD** | Libra esterlina. Amplio rango diario y movimientos direccionales claros. Perfecto para robots de ruptura. |
| **USDJPY** | Yen japonés. Comportamiento técnico estable y alta predecibilidad estadística. |
| **USDCAD** | Dólar canadiense. Patrones repetitivos vinculados a ciclos del petróleo. Muy institucional. |
| **AUDUSD** | Dólar australiano. Movimientos suaves y modelables. Excelente comportamiento estadístico. |
| **NZDUSD** | Dólar neozelandés. Tendencias estables y baja dispersión de ruido. |
| **EURGBP** | Euro / Libra. Volatilidad controlada y movimientos limpios. Óptimo para estrategias de reversión a la media. |
| **AUDJPY** | Dólar australiano / Yen. Correlación directa con el sentimiento de riesgo global. Patrones claros en sesiones asiáticas. |
| **XAGUSD** | Plata. Mayor volatilidad que el oro, ofreciendo oportunidades para modelos de momentum. |

---

## 🧠 Proceso de Entrenamiento del Modelo ONNX

Arion utiliza un pipeline de entrenamiento automatizado que garantiza modelos robustos y actualizados:

1. **Recolección de datos** – El script `MarketTraining.mq5` exporta muestras de 12 dimensiones desde gráficos M15 (hasta 6 años de historial) para cada símbolo, aplicando filtros de calidad y la misma lógica de dirección que usa el EA en vivo.
2. **Combinación de CSVs** – Los archivos generados por cada símbolo se fusionan en un único `KNN.csv` dentro de `MQL5/Files/Arion/`.
3. **Entrenamiento y validación** – El script `train.py` (generado por `AutoTrainManager.mqh`) realiza:
   - Limpieza de valores no finitos y recorte de outliers al percentil 1‑99.
   - División estratificada 80/20 **sin pesos de clase ni balanceos artificiales**.
   - Entrenamiento con XGBoost (`gbtree`, 200 estimadores, max_depth=6).
   - Evaluación de Accuracy, F1‑Score ponderado y reporte de clasificación por clase.
   - Solo se exporta el modelo si se superan los umbrales de calidad (Accuracy ≥ 58%, F1 ≥ 0.57).
   - Se añaden 2 muestras sintéticas neutras por clase faltante exclusivamente para cumplir el requisito técnico de 5 salidas.
4. **Despliegue automático** – El modelo `ArionIntelligence.onnx` y su archivo de normalización `ArionIntelligence.norm` se guardan en `MQL5/Files/Arion/`. El EA detecta cambios por fecha de modificación y **recarga el modelo en caliente** cada 10 segundos sin detener la operativa.

---

## 📦 Requisitos

- **MetaTrader 5** (cualquier build reciente).
- **Python 3.8+** únicamente si se desea ejecutar el reentrenamiento automático (el EA invoca `train.py` mediante `ShellExecuteW`).
- Dependencias Python (se instalan automáticamente): `pandas`, `xgboost`, `onnx`, `skl2onnx`, `scikit-learn`.

---

## ⚙️ Parámetros Principales

| Parámetro | Valor por defecto | Descripción |
|-----------|-------------------|-------------|
| `InpRiskPercentage` | 1.0% | Riesgo porcentual por operación sobre el equity |
| `InpATRMultiplierSL` | 1.5 | Multiplicador del ATR(M1) para Stop Loss |
| `InpRRRatio` | 3.0 | Ratio mínimo Riesgo/Beneficio |
| `InpMaxSpreadPoints` | 50 | Spread máximo permitido en puntos |
| `InpWeightONNX` | 35 | Peso del modelo ONNX en el score |
| `InpWeightKNN` | 25 | Peso del clasificador KNN |
| `InpWeightSMC` | 25 | Peso del análisis SMC |
| `InpWeightContext` | 15 | Peso del contexto de volatilidad |
| `InpApprovalThreshold` | 75.0 | Puntuación mínima para abrir orden |
| `InpMaxDailyLossPercent` | 5.0% | Pérdida diaria máxima sobre equity inicial |
| `InpMaxGlobalTrades` | 15 | Máximo global de posiciones |
| `InpAccountTrailingStop` | 10.0% | Trailing stop sobre equity máximo |
| `InpMaxDailyCredits` | 3 | Créditos diarios para nuevas entradas |
| `InpActivateTrailing` | true | Activar trailing stop individual |
| `InpTrailStartRatio` | 1.5 | Ratio de activación del trailing (ATR * ratio) |
| `InpTrailDistancePips` | 50.0 | Distancia del trailing stop en pips |
| `InpTrailStepPips` | 5.0 | Paso mínimo de actualización del trailing |
| `InpAutoSaveMinutes` | 30 | Intervalo de auto‑guardado (minutos) |
| `InpPythonPath` | `python.exe` | Ruta o comando del ejecutable Python |
| `InpMondayCooldownMinutes` | 30 | Minutos de espera tras apertura del lunes |
| `InpMinNewsImpact` | 3 | Impacto mínimo de noticias para bloqueo (1‑3) |

---

## 📊 Dashboard Global

El panel se muestra en la esquina superior derecha del gráfico y presenta métricas consolidadas de los 10 activos, ordenadas por prioridad de mayor a menor.

| Sección | Indicador | Descripción |
|---------|-----------|-------------|
| **ACCOUNT** | OPS | Total de posiciones abiertas en toda la cuenta |
| | DAY | Ganancia/pérdida del día en dólares |
| | GAIN | Ganancia/pérdida del día en porcentaje |
| **RISK** | DD | Drawdown actual / Máximo diario configurado |
| **MARKET** | SP | Spread actual del símbolo (color según `InpMaxSpreadPoints`) |
| | NEWS | Estado del filtro de noticias (OK / BLOCKED) |
| **CORE IA** | IA | Confianza combinada ONNX + KNN (0‑100%) |
| | CHOP | Índice de Choppiness (verde 38‑62% = tendencia) |
| | VOL | Volatilidad relativa ATR M15 / ATR H4 (valor real) |
| | APR | % de aprobación de la última señal respecto al umbral |
| **ANALYSIS** | SMC | Total de Order Blocks / Fair Value Gaps activos |

---

## 📁 Estructura de Archivos en `MQL5/Files/Arion/`

| Archivo / Carpeta | Descripción |
|-------------------|-------------|
| `SMC\*.bin` | Estado de las zonas SMC por símbolo |
| `KNN\*.bin` | Estado del clasificador KNN por símbolo |
| `KNN.csv` | Dataset combinado para entrenamiento |
| `ArionIntelligence.onnx` | Modelo ONNX de 5 salidas (12 entradas) |
| `ArionIntelligence.norm` | Parámetros de normalización (media y std) |
| `RiskManager.bin` | Estado del gestor de riesgo global |
| `Log.csv` | Bitácora de operaciones y eventos del EA |
| `WF_Report.csv` | Resultados del Walk‑Forward Optimizer |
| `News.csv` | Calendario de noticias (formato `fecha,divisa,impacto`) |
| `MarketTraining.mq5` | Script de recolección de datos históricos |
| `train.py` | Script Python para entrenamiento XGBoost→ONNX |

---

## 🔧 Optimizaciones y Correcciones (v1.0 auditada)

- Eliminación de todos los sesgos estadísticos en indicadores, normalización y modelos.
- Validación estricta de muestras KNN: solo entran datos 100% reales del mercado.
- Cálculo del equity inicial diario desde el historial real de operaciones cerradas.
- Normalización robusta del KNN con mediana e IQR exactos (sin escalas inventadas).
- Autoentrenamiento programado cada 6 horas sin reinicios innecesarios.
- Dashboard con columna APR y colores de spread basados en la tolerancia real configurada.
- Filtro de noticias con impacto real (sin inflar) y zona horaria del servidor del bróker.
- Slippage dinámico ampliado (10‑200 pips) para activos volátiles como XAUUSD.
- Soporte optimizado para cuentas ProCent con apalancamiento 1:1000.
- Archivos de estado organizados en subcarpetas `SMC\` y `KNN\`.
- Contador global de operaciones en carpeta local (no en `FILE_COMMON`).
- Modelo ONNX sin class_weight, sin SMOTE y sin datos sintéticos (solo muestras reales).

---

## 📧 Contacto

**Autor:** Alexy Hernández  
**Email:** alexygeovany@gmail.com  
**GitHub:** [https://github.com/axgeovax](https://github.com/axgeovax)

---

**© 2025 Alexy Hernández. Todos los derechos reservados.**  
**Arion v1.0 – Producto de trading algorítmico profesional.**