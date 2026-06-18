//+------------------------------------------------------------------+
//|                                          AutoTrainManager.mqh    |
//|                                  Arion - Autoentrenamiento       |
//|               Modelo ONNX incrustado con #resource (uchar[])     |
//|                        Autor: Alexy Hernandez                    |
//|                        Version: 1.0                              |
//|   Anadida exportacion automatica del archivo .norm                |
//|   Entrenamiento con datos 100% reales, sin SMOTE ni pesos de clase|
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2025 Alexy Hernandez. All rights reserved."
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
//| Crea el script train.py (12D GBT, SIN class_weight, ONNX, .norm) |
//| Solo usa datos REALES. Sin SMOTE ni pesos de clase.               |
//| * CORREGIDO: anade una muestra sintetica neutra por clase faltante|
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
      Print("Auto-train: Cannot create train.py. Error: ", GetLastError());
      return;
     }

// ---- Python script (comentarios en espanol ASCII, datos reales solamente) ----
   FileWrite(handle, "#!/usr/bin/env python3");
   FileWrite(handle, "\"\"\"");
   FileWrite(handle, "Arion v1.0 - Entrenamiento ONNX 5 clases (12 caracteristicas, booster='gbtree')");
   FileWrite(handle, "Usa solo datos REALES. Sin SMOTE, sin pesos de clase, sin muestras sinteticas.");
   FileWrite(handle, "Umbrales de calidad: exactitud >= 58%, F1 >= 0.57");
   FileWrite(handle, "* CORREGIDO: anade una muestra sintetica por clase faltante para cumplir 5 clases.");
   FileWrite(handle, "\"\"\"");
   FileWrite(handle, "import subprocess, sys, os, argparse, warnings");
   FileWrite(handle, "import numpy as np, pandas as pd, struct, datetime");
   FileWrite(handle, "warnings.filterwarnings('ignore')");
   FileWrite(handle, "");
   FileWrite(handle, "from sklearn.model_selection import StratifiedShuffleSplit");
   FileWrite(handle, "from sklearn.preprocessing import StandardScaler");
   FileWrite(handle, "from sklearn.metrics import accuracy_score, f1_score, classification_report");
   FileWrite(handle, "from xgboost import XGBClassifier");
   FileWrite(handle, "from onnxmltools.convert import convert_xgboost");
   FileWrite(handle, "from onnxmltools.convert.common.data_types import FloatTensorType");
   FileWrite(handle, "import onnx");
   FileWrite(handle, "from onnx import checker");
   FileWrite(handle, "");
   FileWrite(handle, "SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))");
   FileWrite(handle, "");
   FileWrite(handle, "def install_dependencies():");
   FileWrite(handle, "    required = {");
   FileWrite(handle, "        'pandas':'pandas',");
   FileWrite(handle, "        'xgboost':'xgboost',");
   FileWrite(handle, "        'onnx':'onnx',");
   FileWrite(handle, "        'sklearn':'scikit-learn',");
   FileWrite(handle, "        'onnxmltools':'onnxmltools'");
   FileWrite(handle, "    }");
   FileWrite(handle, "    import importlib");
   FileWrite(handle, "    for mod, pkg in required.items():");
   FileWrite(handle, "        try:");
   FileWrite(handle, "            importlib.import_module(mod)");
   FileWrite(handle, "        except ImportError:");
   FileWrite(handle, "            print(f'Installing {pkg}...')");
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
   FileWrite(handle, "def keep_only_probabilities(onnx_model):");
   FileWrite(handle, "    zipmap = next((n for n in onnx_model.graph.node if n.op_type == 'ZipMap'), None)");
   FileWrite(handle, "    if zipmap:");
   FileWrite(handle, "        tensor_name = zipmap.input[0]");
   FileWrite(handle, "        onnx_model.graph.node.remove(zipmap)");
   FileWrite(handle, "    else:");
   FileWrite(handle, "        tensor_name = 'probabilities'");
   FileWrite(handle, "    new_out = [onnx.helper.make_tensor_value_info(tensor_name, onnx.TensorProto.FLOAT, [None, 5])]");
   FileWrite(handle, "    onnx_model.graph.ClearField('output')");
   FileWrite(handle, "    onnx_model.graph.output.extend(new_out)");
   FileWrite(handle, "    checker.check_model(onnx_model)");
   FileWrite(handle, "    return onnx_model");
   FileWrite(handle, "");
   FileWrite(handle, "def train_and_export(csv_file=None, output_model=None):");
   FileWrite(handle, "    if csv_file is None: csv_file = os.path.join(SCRIPT_DIR, 'KNN.csv')");
   FileWrite(handle, "    if output_model is None: output_model = os.path.join(SCRIPT_DIR, 'ArionIntelligence.onnx')");
   FileWrite(handle, "    if not os.path.exists(csv_file):");
   FileWrite(handle, "        print(f'Error: File {csv_file} not found'); return False");
   FileWrite(handle, "    df = pd.read_csv(csv_file)");
   FileWrite(handle, "    feature_cols = ['slope','atr','momentum','volFlow','adx','rsi',");
   FileWrite(handle, "                    'deltaVol','spreadDev','smcRatio','relStrength','normVolatility','volRatio']");
   FileWrite(handle, "    for col in feature_cols + ['direction']:");
   FileWrite(handle, "        if col not in df.columns:");
   FileWrite(handle, "            print(f'Missing column {col}'); return False");
   FileWrite(handle, "    X = df[feature_cols].values.astype(np.float32)");
   FileWrite(handle, "    y = df['direction'].apply(direction_to_class).values.astype(np.int32)");
   FileWrite(handle, "    print(f'Total samples: {len(X)}')");
   FileWrite(handle, "");
   FileWrite(handle, "    X, clean_mask = clean_dataset(X)");
   FileWrite(handle, "    y = y[clean_mask]");
   FileWrite(handle, "    print(f'Samples after cleaning: {len(X)}')");
   FileWrite(handle, "    if len(X) < 100:");
   FileWrite(handle, "        print('Too few samples after cleaning.'); return False");
   FileWrite(handle, "");
   FileWrite(handle, "    for col in range(X.shape[1]):");
   FileWrite(handle, "        p1 = np.percentile(X[:, col], 1)");
   FileWrite(handle, "        p99 = np.percentile(X[:, col], 99)");
   FileWrite(handle, "        X[:, col] = np.clip(X[:, col], p1, p99)");
   FileWrite(handle, "");
   FileWrite(handle, "    unique_classes = np.unique(y)");
   FileWrite(handle, "    print(f'Class distribution (real only): {np.bincount(y)}')");
   FileWrite(handle, "");
   FileWrite(handle, "    # --- ANADIR MUESTRAS SINTETICAS MINIMAS PARA CLASES FALTANTES ---");
   FileWrite(handle, "    expected_classes = np.array([0, 1, 2, 3, 4])");
   FileWrite(handle, "    missing_classes = np.setdiff1d(expected_classes, unique_classes)");
   FileWrite(handle, "    if len(missing_classes) > 0:");
   FileWrite(handle, "        print(f'Missing classes detected: {missing_classes}. Adding one neutral sample per missing class.')");
   FileWrite(handle, "        # Tomar la mediana de cada caracteristica como muestra neutra");
   FileWrite(handle, "        median_features = np.median(X, axis=0)");
   FileWrite(handle, "        for cls in missing_classes:");
   FileWrite(handle, "            X = np.vstack([X, median_features])");
   FileWrite(handle, "            y = np.append(y, cls)");
   FileWrite(handle, "        print(f'New distribution after fill: {np.bincount(y)}')");
   FileWrite(handle, "");
   FileWrite(handle, "    # Division estratificada (preserva proporciones de clase reales)");
   FileWrite(handle, "    sss = StratifiedShuffleSplit(n_splits=1, test_size=0.2, random_state=42)");
   FileWrite(handle, "    for train_idx, test_idx in sss.split(X, y):");
   FileWrite(handle, "        X_train, X_test = X[train_idx], X[test_idx]");
   FileWrite(handle, "        y_train, y_test = y[train_idx], y[test_idx]");
   FileWrite(handle, "");
   FileWrite(handle, "    # Escalar datos con la media y desviacion estandar reales");
   FileWrite(handle, "    scaler = StandardScaler()");
   FileWrite(handle, "    X_train_scaled = scaler.fit_transform(X_train)");
   FileWrite(handle, "    X_test_scaled  = scaler.transform(X_test)");
   FileWrite(handle, "");
   FileWrite(handle, "    # Entrenar modelo GBT SIN pesos de clase (distribucion real del mercado)");
   FileWrite(handle, "    model = XGBClassifier(");
   FileWrite(handle, "        booster='gbtree',");
   FileWrite(handle, "        objective='multi:softprob',");
   FileWrite(handle, "        num_class=5,");
   FileWrite(handle, "        max_depth=6,");
   FileWrite(handle, "        learning_rate=0.1,");
   FileWrite(handle, "        n_estimators=200,");
   FileWrite(handle, "        subsample=0.8,");
   FileWrite(handle, "        colsample_bytree=0.8,");
   FileWrite(handle, "        reg_lambda=1.0,");
   FileWrite(handle, "        reg_alpha=0.5,");
   FileWrite(handle, "        random_state=42,");
   FileWrite(handle, "        verbosity=0");
   FileWrite(handle, "    )");
   FileWrite(handle, "    model.fit(X_train_scaled, y_train)");
   FileWrite(handle, "    y_pred = model.predict(X_test_scaled)");
   FileWrite(handle, "    acc = accuracy_score(y_test, y_pred)");
   FileWrite(handle, "    f1  = f1_score(y_test, y_pred, average='weighted')");
   FileWrite(handle, "    print(f'Test accuracy: {acc:.2%}')");
   FileWrite(handle, "    print(f'Weighted F1-score: {f1:.4f}')");
   FileWrite(handle, "    target_names = ['Strong Sell','Sell','Neutral','Buy','Strong Buy']");
   FileWrite(handle, "    print(classification_report(y_test, y_pred, target_names=target_names))");
   FileWrite(handle, "");
   FileWrite(handle, "    if acc < 0.58 or f1 < 0.57:");
   FileWrite(handle, "        print('Quality thresholds not met. Model not saved.'); return False");
   FileWrite(handle, "");
   FileWrite(handle, "    # Exportar ONNX");
   FileWrite(handle, "    initial_type = [('float_input', FloatTensorType([None, 12]))]");
   FileWrite(handle, "    onx = convert_xgboost(model, initial_types=initial_type, target_opset=12)");
   FileWrite(handle, "    onx = keep_only_probabilities(onx)");
   FileWrite(handle, "    with open(output_model, 'wb') as f:");
   FileWrite(handle, "        f.write(onx.SerializeToString())");
   FileWrite(handle, "    print(f'ONNX model saved: {output_model} ({os.path.getsize(output_model)} bytes)')");
   FileWrite(handle, "");
   FileWrite(handle, "    # Guardar parametros de normalizacion (StandardScaler)");
   FileWrite(handle, "    norm_path = output_model.replace('.onnx', '.norm')");
   FileWrite(handle, "    with open(norm_path, 'wb') as f:");
   FileWrite(handle, "        for v in scaler.mean_:");
   FileWrite(handle, "            f.write(struct.pack('d', v))");
   FileWrite(handle, "        for v in scaler.scale_:");
   FileWrite(handle, "            f.write(struct.pack('d', v))");
   FileWrite(handle, "    print(f'Normalization params saved: {norm_path}')");
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
   Print("Auto-training script train.py (gbtree + onnxmltools + .norm export) created successfully.");
  }

//+------------------------------------------------------------------+
//| Intenta ejecutar Python usando customPath + candidatos + PATH     |
//+------------------------------------------------------------------+
bool RunPythonScript(string arguments, string customPath = "", bool showWindow = false)
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
   int showCmd = showWindow ? 1 : 0;

// 1. Intentar el path personalizado (input del usuario)
   if(customPath != "")
     {

      if(ShellExecuteW(0, "open", customPath, cmd, workingDir, showCmd) > 32)
        {
         Print("Python ejecutado con path personalizado: ", customPath);
         return true;
        }
      Print("No se pudo ejecutar el path personalizado: ", customPath);
     }

// 2. Intentar la lista de candidatos predefinidos
   for(int i = 0; i < ArraySize(pythonCandidates); i++)
     {

      if(ShellExecuteW(0, "open", pythonCandidates[i], cmd, workingDir, showCmd) > 32)
        {
         Print("Python encontrado en: ", pythonCandidates[i]);
         return true;
        }
     }

// 3. Ultimo intento: solo "python" o "python3" (depende del PATH del sistema)

   if(ShellExecuteW(0, "open", "python", cmd, workingDir, showCmd) > 32)
     {
      Print("Python ejecutado desde el PATH del sistema.");
      return true;
     }

   if(ShellExecuteW(0, "open", "python3", cmd, workingDir, showCmd) > 32)
     {
      Print("Python3 ejecutado desde el PATH del sistema.");
      return true;
     }

   Print("ERROR: No se encontro ningun ejecutable de Python.");
   Print("   Configure la ruta correcta en el parametro 'InpPythonPath' del EA.");
   return false;
  }

//+------------------------------------------------------------------+
//| Ejecuta el script Python de reentrenamiento (asincrono)           |
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

   RunPythonScript(args, InpPythonPath, InpShowPythonWindow);
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
