# Arion v1.0 - Institutional Multi-Currency EA

![Versión](https://img.shields.io/badge/versión-1.0-blue)
![Plataforma](https://img.shields.io/badge/plataforma-MetaTrader%205-green)
![Estado](https://img.shields.io/badge/estado-Producción-brightgreen)
![Acceso](https://img.shields.io/badge/acceso-Privado-red)

**Arion** es un Expert Advisor institucional multidivisa para MetaTrader 5 que combina **Smart Money Concepts (SMC) fractal dinámico**, **inteligencia artificial híbrida (ONNX 12D + KNN 12D)** y **gestión de riesgo global adaptativa** para operar automáticamente una cartera diversificada de 10 activos con un perfil riesgo‑beneficio objetivo de 1:3.

---

## 🚀 Características Principales

- **IA Híbrida Evolutiva 12D** – Modelo ONNX de 5 salidas con 12 características de entrada y clasificador KNN de 12 dimensiones que aprende en tiempo real. El modelo se reentrena periódicamente con datos reales de todos los activos del portafolio.
- **Pipeline de Autoentrenamiento Robusto** – Script `train.py` generado automáticamente que balancea clases mediante submuestreo, entrena XGBoost (`gbtree`) y produce `ArionIntelligence.onnx` (12 entradas, 5 salidas) compatible con MetaTrader 5.
- **SMC Fractal Dinámico** – Detección de Order Blocks, Fair Value Gaps, Choppiness Index, Liquidity Pools y dirección macro de 5 clases (`Strong Sell` a `Strong Buy`) sin dependencia de timeframes fijos.
- **Gestión de Riesgo Global** – Límite diario de pérdidas, trailing stop de cuenta, créditos diarios por operación, cierre selectivo de emergencia y factor de reducción por correlación adaptativo (matriz dual D1/M15).
- **Ejecución Avanzada** – Órdenes asíncronas con smart order routing (FOK → IOC → RETURN), slippage dinámico por ATR, margen de seguridad variable y trailing stop individual adaptativo.
- **Dashboard Global en Tiempo Real** – Panel con métricas consolidadas de los 10 activos: exposición, drawdown, spread, bloqueo por noticias, confianza de IA, Choppiness, volatilidad, zonas SMC activas y desacople institucional.
- **Persistencia y Resiliencia** – Auto‑guardado periódico y por eventos con sistema Safe Save (archivo temporal + renombrado) para prevenir corrupción de datos.

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

1. **Recolección de datos** – El script `MarketTraining.mq5` exporta muestras de 12 dimensiones desde gráficos M15 (hasta 5 años de historial) para cada símbolo, aplicando filtros de calidad y clasificación híbrida (SMC + heurística adaptativa).
2. **Combinación de CSVs** – Los archivos generados se combinan en un único `KNN.csv` dentro de `MQL5/Files/Arion/`.
3. **Entrenamiento y validación** – El script `train.py` (generado por `AutoTrainManager.mqh`) realiza:
   - Limpieza de valores infinitos y recorte de outliers.
   - Submuestreo de clases mayoritarias para balancear el dataset.
   - División estratificada 80/20 y entrenamiento con XGBoost (`gbtree`, 250 estimadores).
   - Evaluación de Accuracy, F1‑Score y matriz de confusión.
   - Reentrenamiento lineal (`gblinear`) para extraer pesos y sesgo, y construcción del grafo ONNX `Gemm + Softmax`.
   - Solo se exporta el modelo si se superan los umbrales de calidad (Accuracy ≥ 60%, F1 ≥ 0.55).
4. **Despliegue automático** – El modelo `ArionIntelligence.onnx` se guarda en `MQL5/Files/Arion/` y el EA lo recarga en caliente cada 10 segundos sin detener la operativa.

---

## 📦 Requisitos

- **MetaTrader 5** (cualquier build reciente).
- **Python 3.8+** únicamente si se desea ejecutar el reentrenamiento automático (el EA invoca `train.py` mediante `ShellExecuteW`).
- Dependencias Python (se instalan automáticamente): `pandas`, `xgboost`, `onnx`, `skl2onnx`, `scikit-learn`, `imbalanced-learn`.

---

## ⚙️ Parámetros Principales

| Parámetro | Valor por defecto | Descripción |
|-----------|-------------------|-------------|
| `InpRiskPercentage` | 1.0% | Riesgo porcentual por operación |
| `InpATRMultiplierSL` | 1.5 | Multiplicador del ATR para Stop Loss |
| `InpRRRatio` | 3.0 | Ratio mínimo Riesgo/Beneficio |
| `InpMaxSpreadPoints` | 50 | Spread máximo permitido en puntos |
| `InpWeightONNX` | 35 | Peso del modelo ONNX en el score |
| `InpWeightKNN` | 25 | Peso del clasificador KNN |
| `InpWeightSMC` | 25 | Peso del análisis SMC |
| `InpWeightContext` | 15 | Peso del contexto de volatilidad |
| `InpApprovalThreshold` | 75.0 | Puntuación mínima para abrir orden |
| `InpMaxDailyLossPercent` | 5.0% | Pérdida diaria máxima |
| `InpMaxGlobalTrades` | 15 | Máximo global de posiciones |
| `InpAccountTrailingStop` | 10.0% | Trailing stop sobre equity máximo |
| `InpMaxDailyCredits` | 3 | Créditos diarios para nuevas entradas |
| `InpActivateTrailing` | true | Activar trailing stop individual |
| `InpAutoSaveMinutes` | 30 | Intervalo de auto‑guardado (minutos) |
| `InpPythonPath` | `python.exe` | Ruta o comando del ejecutable Python |

---

## 📊 Dashboard Global

El panel se muestra en la esquina superior derecha del gráfico y presenta métricas consolidadas de los 10 activos.

| Sección | Indicador | Descripción |
|---------|-----------|-------------|
| **ACCOUNT** | OPS | Total de posiciones abiertas en toda la cuenta |
| | DAY | Ganancia/pérdida del día en dólares |
| | GAIN | Ganancia/pérdida del día en porcentaje |
| **RISK** | DD | Drawdown actual / Máximo diario configurado |
| **MARKET** | SP | Spread promedio de los 10 activos |
| | NEWS | Estado del filtro de noticias (OK / BLOCKED) |
| | DEC | Número de pares en desacople institucional |
| **CORE IA** | IA | Confianza combinada ONNX + KNN (promedio) |
| | CHOP | Índice de Choppiness promedio (M15) |
| | MODEL | Estado del modelo ONNX (EVOLUTIVE / STATIC) |
| **ANALYSIS** | VOL | Volatilidad relativa promedio (M1/M15) |
| | SMC | Total de Order Blocks / Fair Value Gaps activos |

---

## 📁 Estructura de Archivos en `MQL5/Files/Arion/`

| Archivo | Descripción |
|---------|-------------|
| `KNN_[SYMBOL].bin` | Estado del clasificador KNN por símbolo |
| `SMC_[SYMBOL].bin` | Estado de las zonas SMC por símbolo |
| `KNN.csv` | Dataset combinado para entrenamiento |
| `ArionIntelligence.onnx` | Modelo ONNX de 5 salidas (12 entradas) |
| `Log.csv` | Bitácora de operaciones y eventos del EA |
| `WF_Report.csv` | Resultados del Walk‑Forward Optimizer |
| `News.csv` | Calendario de noticias (formato `fecha,divisa,impacto`) |

---

## 📧 Contacto

**Autor:** Alexy Hernández  
**Email:** axgeovax@gmail.com  
**GitHub:** [https://github.com/axgeovax](https://github.com/axgeovax)

---

**© 2025 Alexy Hernández. Todos los derechos reservados.**  
**Arion v1.0 – Producto de trading algorítmico profesional.**