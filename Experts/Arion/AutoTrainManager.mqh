//+------------------------------------------------------------------+
//|                                          AutoTrainManager.mqh    |
//|                                  Arion - Autoentrenamiento       |
//|               Modelo ONNX incrustado con #resource (uchar[])     |
//|                        Autor: Alexy Hernández                    |
//|                        Versión: 1.0                              |
//|        Copyright (c) 2025 Alexy Hernández. Todos los derechos    |
//|        reservados.                                               |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernández. Todos los derechos reservados."
#property link      "https://github.com/axgeovax"
#property version   "1.0"
#property strict

#ifndef __AUTOTRAINMANAGER_MQH__
#define __AUTOTRAINMANAGER_MQH__

//+------------------------------------------------------------------+
//| Helper: asegura que la carpeta Arion exista en Files             |
//+------------------------------------------------------------------+
void EnsureArionFolder()
  {
   string folder = "Arion";
   if(!FolderCreate(folder))
      ResetLastError();
  }

//+------------------------------------------------------------------+
//| Crea el script train.py (12D, balanceo avanzado con submuestreo) |
//| Maneja la ausencia de la clase Neutral expandiendo pesos a 5x5   |
//| Incluye limpieza de datos y balanceo de clases                   |
//+------------------------------------------------------------------+
void CreateTrainScriptIfMissing()
  {
   EnsureArionFolder();
   string scriptPath = "Arion\\train.py";
   if(FileIsExist(scriptPath))
      return;

   int handle = FileOpen(scriptPath, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
     {
      Print("Auto‑train: Cannot create train.py. Error: ", GetLastError());
      return;
     }

// ---- Script Python 12D (balanceo avanzado con submuestreo) ----
   FileWrite(handle, "#!/usr/bin/env python3");
   FileWrite(handle, "\"\"\"");
   FileWrite(handle, "Arion v1.0 - Entrenamiento ONNX 5 clases (12 features, balanceo avanzado)");
   FileWrite(handle, "Maneja la ausencia de la clase Neutral expandiendo la matriz de pesos.");
   FileWrite(handle, "\"\"\"");
   FileWrite(handle, "import subprocess, sys, os, argparse, warnings, numpy as np, pandas as pd");
   FileWrite(handle, "warnings.filterwarnings('ignore')");
   FileWrite(handle, "");
   FileWrite(handle, "from sklearn.model_selection import train_test_split");
   FileWrite(handle, "from sklearn.preprocessing import RobustScaler");
   FileWrite(handle, "from sklearn.pipeline import Pipeline");
   FileWrite(handle, "from sklearn.metrics import accuracy_score, f1_score, classification_report");
   FileWrite(handle, "from xgboost import XGBClassifier");
   FileWrite(handle, "from onnx import helper, TensorProto, OperatorSetIdProto");
   FileWrite(handle, "");
   FileWrite(handle, "SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))");
   FileWrite(handle, "");
   FileWrite(handle, "def install_dependencies():");
   FileWrite(handle, "    required = {");
   FileWrite(handle, "        'pandas':'pandas',");
   FileWrite(handle, "        'xgboost':'xgboost',");
   FileWrite(handle, "        'onnx':'onnx',");
   FileWrite(handle, "        'skl2onnx':'skl2onnx',");
   FileWrite(handle, "        'sklearn':'scikit-learn',");
   FileWrite(handle, "        'imblearn':'imbalanced-learn'");
   FileWrite(handle, "    }");
   FileWrite(handle, "    import importlib");
   FileWrite(handle, "    for mod, pkg in required.items():");
   FileWrite(handle, "        try:");
   FileWrite(handle, "            importlib.import_module(mod)");
   FileWrite(handle, "        except ImportError:");
   FileWrite(handle, "            print(f'Instalando {pkg}...')");
   FileWrite(handle, "            subprocess.check_call([sys.executable, '-m', 'pip', 'install', pkg],");
   FileWrite(handle, "                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)");
   FileWrite(handle, "");
   FileWrite(handle, "def direction_to_class(d):");
   FileWrite(handle, "    m = {-1:0, -0.5:1, 0:2, 0.5:3, 1:4}");
   FileWrite(handle, "    return m.get(d, 2)");
   FileWrite(handle, "");
   FileWrite(handle, "def clean_dataset(X):");
   FileWrite(handle, "    X = np.where(np.isfinite(X), X, np.nan)");
   FileWrite(handle, "    mask = ~np.isnan(X).any(axis=1)");
   FileWrite(handle, "    return X[mask], mask");
   FileWrite(handle, "");
   FileWrite(handle, "def train_and_export(csv_file=None, output_model=None):");
   FileWrite(handle, "    if csv_file is None: csv_file = os.path.join(SCRIPT_DIR, 'KNN.csv')");
   FileWrite(handle, "    if output_model is None: output_model = os.path.join(SCRIPT_DIR, 'ArionIntelligence.onnx')");
   FileWrite(handle, "    if not os.path.exists(csv_file):");
   FileWrite(handle, "        print(f'Error: No se encontro {csv_file}'); return False");
   FileWrite(handle, "    df = pd.read_csv(csv_file)");
   FileWrite(handle, "    feature_cols = ['slope','atr','momentum','volFlow','adx','rsi',");
   FileWrite(handle, "                    'deltaVol','spreadDev','smcRatio','relStrength','normVolatility','volRatio']");
   FileWrite(handle, "    for col in feature_cols + ['direction']:");
   FileWrite(handle, "        if col not in df.columns:");
   FileWrite(handle, "            print(f'Falta columna {col}'); return False");
   FileWrite(handle, "    X = df[feature_cols].values.astype(np.float32)");
   FileWrite(handle, "    y = df['direction'].apply(direction_to_class).values.astype(np.int32)");
   FileWrite(handle, "    print(f'Muestras totales: {len(X)}')");
   FileWrite(handle, "");
   FileWrite(handle, "    # Limpieza de valores infinitos y extremos");
   FileWrite(handle, "    X, clean_mask = clean_dataset(X)");
   FileWrite(handle, "    y = y[clean_mask]");
   FileWrite(handle, "    print(f'Muestras tras limpieza: {len(X)}')");
   FileWrite(handle, "    if len(X) < 100:");
   FileWrite(handle, "        print('Muy pocas muestras tras la limpieza.'); return False");
   FileWrite(handle, "");
   FileWrite(handle, "    # Recortar valores extremos (percentil 1-99)");
   FileWrite(handle, "    for col in range(X.shape[1]):");
   FileWrite(handle, "        p1 = np.percentile(X[:, col], 1)");
   FileWrite(handle, "        p99 = np.percentile(X[:, col], 99)");
   FileWrite(handle, "        X[:, col] = np.clip(X[:, col], p1, p99)");
   FileWrite(handle, "");
   FileWrite(handle, "    # Detectar clases presentes");
   FileWrite(handle, "    unique_y = np.unique(y)");
   FileWrite(handle, "    present = sorted(unique_y)");
   FileWrite(handle, "    print(f'Clases presentes: {present}')");
   FileWrite(handle, "    missing = sorted(set(range(5)) - set(present))");
   FileWrite(handle, "    if missing:");
   FileWrite(handle, "        class_names = ['Strong Sell','Sell','Neutral','Buy','Strong Buy']");
   FileWrite(handle, "        for cls in missing:");
   FileWrite(handle, "            print(f'Falta clase real: {cls} ({class_names[cls]})')");
   FileWrite(handle, "        if 2 in missing and len(present) >= 4:");
   FileWrite(handle, "            print('Se entrenara un modelo de 4 clases (sin Neutral) y se expandira a 5 salidas.')");
   FileWrite(handle, "        else:");
   FileWrite(handle, "            print('El CSV no contiene suficientes clases. No se genero modelo.')");
   FileWrite(handle, "            return False");
   FileWrite(handle, "");
   FileWrite(handle, "    # Mapear las clases presentes a indices 0..k-1 para el entrenamiento");
   FileWrite(handle, "    unique_classes = sorted(present)");
   FileWrite(handle, "    class_to_idx = {cls: i for i, cls in enumerate(unique_classes)}");
   FileWrite(handle, "    y_train = np.array([class_to_idx[val] for val in y])");
   FileWrite(handle, "    num_train_classes = len(unique_classes)");
   FileWrite(handle, "");
   FileWrite(handle, "    # Submuestreo de clases mayoritarias para balancear");
   FileWrite(handle, "    from imblearn.under_sampling import RandomUnderSampler");
   FileWrite(handle, "    rus = RandomUnderSampler(random_state=42, sampling_strategy='not minority')");
   FileWrite(handle, "    X_res, y_res = rus.fit_resample(X, y_train)");
   FileWrite(handle, "    print(f'Muestras tras submuestreo: {len(X_res)}')");
   FileWrite(handle, "");
   FileWrite(handle, "    # Division estratificada 80/20");
   FileWrite(handle, "    X_train, X_test, y_train_split, y_test_split = train_test_split(");
   FileWrite(handle, "        X_res, y_res, test_size=0.2, random_state=42, stratify=y_res)");
   FileWrite(handle, "");
   FileWrite(handle, "    # Pipeline con RobustScaler + XGBoost");
   FileWrite(handle, "    model = Pipeline([");
   FileWrite(handle, "        ('scaler', RobustScaler()),");
   FileWrite(handle, "        ('xgb', XGBClassifier(");
   FileWrite(handle, "            booster='gbtree',");
   FileWrite(handle, "            objective='multi:softprob',");
   FileWrite(handle, "            num_class=num_train_classes,");
   FileWrite(handle, "            n_estimators=250,");
   FileWrite(handle, "            max_depth=6,");
   FileWrite(handle, "            learning_rate=0.03,");
   FileWrite(handle, "            subsample=0.8,");
   FileWrite(handle, "            colsample_bytree=0.8,");
   FileWrite(handle, "            reg_lambda=0.1,");
   FileWrite(handle, "            random_state=42,");
   FileWrite(handle, "            verbosity=0");
   FileWrite(handle, "        ))");
   FileWrite(handle, "    ])");
   FileWrite(handle, "    model.fit(X_train, y_train_split)");
   FileWrite(handle, "    y_pred = model.predict(X_test)");
   FileWrite(handle, "    acc = accuracy_score(y_test_split, y_pred)");
   FileWrite(handle, "    f1  = f1_score(y_test_split, y_pred, average='weighted')");
   FileWrite(handle, "");
   FileWrite(handle, "    print(f'Accuracy en test: {acc:.2%}')");
   FileWrite(handle, "    print(f'F1-Score ponderado: {f1:.4f}')");
   FileWrite(handle, "    target_names = [['Strong Sell','Sell','Neutral','Buy','Strong Buy'][i] for i in unique_classes]");
   FileWrite(handle, "    print(classification_report(y_test_split, y_pred, target_names=target_names))");
   FileWrite(handle, "");
   FileWrite(handle, "    # Umbrales de calidad RELAJADOS (60% accuracy, 0.55 F1)");
   FileWrite(handle, "    if acc < 0.60 or f1 < 0.55:");
   FileWrite(handle, "        print('Umbrales de calidad no superados. No se genero modelo.'); return False");
   FileWrite(handle, "");
   FileWrite(handle, "    # Reentrenar con gblinear para obtener pesos explicitos");
   FileWrite(handle, "    linear_model = XGBClassifier(");
   FileWrite(handle, "        booster='gblinear',");
   FileWrite(handle, "        objective='multi:softprob',");
   FileWrite(handle, "        num_class=num_train_classes,");
   FileWrite(handle, "        reg_lambda=0.1,");
   FileWrite(handle, "        learning_rate=0.1,");
   FileWrite(handle, "        n_estimators=100,");
   FileWrite(handle, "        random_state=42");
   FileWrite(handle, "    )");
   FileWrite(handle, "    linear_model.fit(X_train, y_train_split)");
   FileWrite(handle, "    coef = linear_model.coef_");
   FileWrite(handle, "    intercept = linear_model.intercept_");
   FileWrite(handle, "    print(f'coef_ shape: {coef.shape}, intercept_ shape: {intercept.shape}')");
   FileWrite(handle, "");
   FileWrite(handle, "    # Construir matriz de pesos 5x12 y sesgo 5");
   FileWrite(handle, "    W = np.zeros((5, 12), dtype=np.float32)");
   FileWrite(handle, "    B = np.zeros(5, dtype=np.float32)");
   FileWrite(handle, "    for i, cls in enumerate(unique_classes):");
   FileWrite(handle, "        if coef.shape[0] == num_train_classes:");
   FileWrite(handle, "            W[cls, :] = coef[i, :]");
   FileWrite(handle, "        else:");
   FileWrite(handle, "            W[cls, :] = coef[i, :12]");
   FileWrite(handle, "        if intercept is not None and len(intercept) == num_train_classes:");
   FileWrite(handle, "            B[cls] = intercept[i]");
   FileWrite(handle, "");
   FileWrite(handle, "    # Normalizar pesos");
   FileWrite(handle, "    scale = np.max(np.abs(W)) + 1e-6");
   FileWrite(handle, "    W /= scale");
   FileWrite(handle, "    B /= scale");
   FileWrite(handle, "");
   FileWrite(handle, "    # Construir grafo ONNX (entrada 12, salida 5)");
   FileWrite(handle, "    X_tensor = helper.make_tensor_value_info('float_input', TensorProto.FLOAT, [1, 12])");
   FileWrite(handle, "    Y_tensor = helper.make_tensor_value_info('probabilities', TensorProto.FLOAT, [1, 5])");
   FileWrite(handle, "");
   FileWrite(handle, "    weight_init = helper.make_tensor('weight', TensorProto.FLOAT, [5, 12], W.flatten().tolist())");
   FileWrite(handle, "    bias_init   = helper.make_tensor('bias',   TensorProto.FLOAT, [5],    B.tolist())");
   FileWrite(handle, "");
   FileWrite(handle, "    gemm = helper.make_node('Gemm', inputs=['float_input','weight','bias'], outputs=['logits'], alpha=1.0, beta=1.0, transB=1)");
   FileWrite(handle, "    soft = helper.make_node('Softmax', inputs=['logits'], outputs=['probabilities'], axis=1)");
   FileWrite(handle, "    graph = helper.make_graph([gemm, soft], 'Arion12DModel', [X_tensor], [Y_tensor], [weight_init, bias_init])");
   FileWrite(handle, "    opset = OperatorSetIdProto(); opset.version = 12");
   FileWrite(handle, "    model_onnx = helper.make_model(graph, opset_imports=[opset], producer_name='Arion')");
   FileWrite(handle, "");
   FileWrite(handle, "    with open(output_model, 'wb') as f:");
   FileWrite(handle, "        f.write(model_onnx.SerializeToString())");
   FileWrite(handle, "    print(f'Modelo ONNX guardado: {output_model} ({os.path.getsize(output_model)} bytes)')");
   FileWrite(handle, "    return True");
   FileWrite(handle, "");
   FileWrite(handle, "def main():");
   FileWrite(handle, "    install_dependencies()");
   FileWrite(handle, "    parser = argparse.ArgumentParser()");
   FileWrite(handle, "    parser.add_argument('--csv', default=None); parser.add_argument('--output', default=None)");
   FileWrite(handle, "    args = parser.parse_args()");
   FileWrite(handle, "    if not train_and_export(args.csv, args.output): sys.exit(1)");
   FileWrite(handle, "");
   FileWrite(handle, "if __name__ == '__main__':");
   FileWrite(handle, "    main()");

   FileClose(handle);
   Print("Auto‑training script train.py (12D + balanceo avanzado) created successfully.");
  }

//+------------------------------------------------------------------+
//| Intenta ejecutar Python usando customPath + candidatos + PATH     |
//+------------------------------------------------------------------+
bool RunPythonScript(string arguments, string customPath = "")
  {
   string pythonCandidates[] =
     {
      "python.exe", "python3.exe",
      "C:\\Python39\\python.exe", "C:\\Python310\\python.exe", "C:\\Python311\\python.exe",
      "C:\\Python312\\python.exe", "C:\\Python313\\python.exe",
      "C:\\Program Files\\Python39\\python.exe", "C:\\Program Files\\Python310\\python.exe",
      "C:\\Program Files\\Python311\\python.exe", "C:\\Program Files\\Python312\\python.exe",
      "C:\\Program Files\\Python313\\python.exe"
     };

   string scriptPath = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\Arion\\train.py";
   string workingDir = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\Arion";
   string cmd = "\"" + scriptPath + "\" " + arguments;

// 1. Intentar el path personalizado (input del usuario)
   if(customPath != "")
     {
      if(ShellExecuteW(0, "open", customPath, cmd, workingDir, 1) > 32)
        {
         Print("✅ Python ejecutado con path personalizado: ", customPath);
         return true;
        }
      Print("⚠ No se pudo ejecutar el path personalizado: ", customPath);
     }

// 2. Intentar la lista de candidatos predefinidos
   for(int i = 0; i < ArraySize(pythonCandidates); i++)
     {
      if(ShellExecuteW(0, "open", pythonCandidates[i], cmd, workingDir, 1) > 32)
        {
         Print("✅ Python encontrado en: ", pythonCandidates[i]);
         return true;
        }
     }

// 3. Último intento: solo "python" o "python3" (depende del PATH del sistema)
   if(ShellExecuteW(0, "open", "python", cmd, workingDir, 1) > 32)
     {
      Print("✅ Python ejecutado desde el PATH del sistema.");
      return true;
     }
   if(ShellExecuteW(0, "open", "python3", cmd, workingDir, 1) > 32)
     {
      Print("✅ Python3 ejecutado desde el PATH del sistema.");
      return true;
     }

   Print("❌ ERROR: No se encontró ningún ejecutable de Python.");
   Print("   Configure la ruta correcta en el parámetro 'InpPythonPath' del EA.");
   return false;
  }

//+------------------------------------------------------------------+
//| Ejecuta el script Python de reentrenamiento (asíncrono)           |
//+------------------------------------------------------------------+
void ExecutePythonTrainer()
  {
   static datetime lastAttempt = 0;
   if(TimeCurrent() - lastAttempt < 21600)
      return;
   lastAttempt = TimeCurrent();

   CreateTrainScriptIfMissing();

   string csvPath  = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\Arion\\KNN.csv";
   string onnxPath = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\Arion\\ArionIntelligence.onnx";
   string args = "--csv \"" + csvPath + "\" --output \"" + onnxPath + "\"";

   RunPythonScript(args, InpPythonPath);
  }

//+------------------------------------------------------------------+
//| Extrae el modelo ONNX del recurso embebido si no existe           |
//+------------------------------------------------------------------+
void EnsureInitialOnnxModel()
  {
   EnsureArionFolder();
   string onnxPath = "Arion\\ArionIntelligence.onnx";
   if(FileIsExist(onnxPath))
     {
      int h = FileOpen(onnxPath, FILE_READ | FILE_BIN);
      if(h != INVALID_HANDLE)
        {
         if(FileSize(h) > 100)
           {
            FileClose(h);
            return;
           }
         FileClose(h);
        }
     }

   Print("Extracting embedded ONNX model from resource...");
   if(ArraySize(onnx_resource_data) == 0)
     {
      Print("Error: Embedded ONNX resource is empty.");
      return;
     }

   int handle = FileOpen(onnxPath, FILE_WRITE | FILE_BIN);
   if(handle == INVALID_HANDLE)
     {
      Print("Error: Cannot create ONNX file in Files\\Arion folder. Error: ", GetLastError());
      return;
     }

   FileWriteArray(handle, onnx_resource_data, 0, ArraySize(onnx_resource_data));
   FileClose(handle);

   Print("Initial ONNX model extracted successfully (", ArraySize(onnx_resource_data), " bytes) to MQL5\\Files\\Arion.");
  }

#import "shell32.dll"
int ShellExecuteW(int hWnd, string lpOperation, string lpFile, string lpParameters, string lpDirectory, int nShowCmd);
#import

#endif // __AUTOTRAINMANAGER_MQH__
//+------------------------------------------------------------------+
