#!/usr/bin/env python3
"""
Arion v1.0 - Entrenamiento ONNX 5 clases (12 caracteristicas, booster='gbtree')
Usa solo datos REALES. Sin SMOTE, sin pesos de clase, sin muestras sinteticas.
Umbrales de calidad: exactitud >= 58%, F1 >= 0.57
* CORREGIDO: anade una muestra sintetica por clase faltante para cumplir 5 clases.
"""
import subprocess, sys, os, argparse, warnings
import numpy as np, pandas as pd, struct, datetime
warnings.filterwarnings('ignore')

from sklearn.model_selection import StratifiedShuffleSplit
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import accuracy_score, f1_score, classification_report
from xgboost import XGBClassifier
from onnxmltools.convert import convert_xgboost
from onnxmltools.convert.common.data_types import FloatTensorType
import onnx
from onnx import checker

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

def install_dependencies():
    required = {
        'pandas':'pandas',
        'xgboost':'xgboost',
        'onnx':'onnx',
        'sklearn':'scikit-learn',
        'onnxmltools':'onnxmltools'
    }
    import importlib
    for mod, pkg in required.items():
        try:
            importlib.import_module(mod)
        except ImportError:
            print(f'Installing {pkg}...')
            subprocess.check_call([sys.executable, '-m', 'pip', 'install', pkg],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def direction_to_class(d):
    m = {-1:0, -0.5:1, 0:2, 0.5:3, 1:4}
    return m.get(d, 2)

def clean_dataset(X):
    X = np.where(np.isfinite(X), X, np.nan)
    mask = ~np.isnan(X).any(axis=1)
    return X[mask], mask

def keep_only_probabilities(onnx_model):
    zipmap = next((n for n in onnx_model.graph.node if n.op_type == 'ZipMap'), None)
    if zipmap:
        tensor_name = zipmap.input[0]
        onnx_model.graph.node.remove(zipmap)
    else:
        tensor_name = 'probabilities'
    new_out = [onnx.helper.make_tensor_value_info(tensor_name, onnx.TensorProto.FLOAT, [None, 5])]
    onnx_model.graph.ClearField('output')
    onnx_model.graph.output.extend(new_out)
    checker.check_model(onnx_model)
    return onnx_model

def train_and_export(csv_file=None, output_model=None):
    if csv_file is None: csv_file = os.path.join(SCRIPT_DIR, 'KNN.csv')
    if output_model is None: output_model = os.path.join(SCRIPT_DIR, 'ArionIntelligence.onnx')
    if not os.path.exists(csv_file):
        print(f'Error: File {csv_file} not found'); return False
    df = pd.read_csv(csv_file)
    feature_cols = ['slope','atr','momentum','volFlow','adx','rsi',
                    'deltaVol','spreadDev','smcRatio','relStrength','normVolatility','volRatio']
    for col in feature_cols + ['direction']:
        if col not in df.columns:
            print(f'Missing column {col}'); return False
    X = df[feature_cols].values.astype(np.float32)
    y = df['direction'].apply(direction_to_class).values.astype(np.int32)
    print(f'Total samples: {len(X)}')

    X, clean_mask = clean_dataset(X)
    y = y[clean_mask]
    print(f'Samples after cleaning: {len(X)}')
    if len(X) < 100:
        print('Too few samples after cleaning.'); return False

    for col in range(X.shape[1]):
        p1 = np.percentile(X[:, col], 1)
        p99 = np.percentile(X[:, col], 99)
        X[:, col] = np.clip(X[:, col], p1, p99)

    unique_classes = np.unique(y)
    print(f'Class distribution (real only): {np.bincount(y)}')

    # --- ANADIR MUESTRAS SINTETICAS MINIMAS PARA CLASES FALTANTES ---
    expected_classes = np.array([0, 1, 2, 3, 4])
    missing_classes = np.setdiff1d(expected_classes, unique_classes)
    if len(missing_classes) > 0:
        print(f'Missing classes detected: {missing_classes}. Adding one neutral sample per missing class.')
        # Tomar la mediana de cada caracteristica como muestra neutra
        median_features = np.median(X, axis=0)
        for cls in missing_classes:
            X = np.vstack([X, median_features])
            y = np.append(y, cls)
        print(f'New distribution after fill: {np.bincount(y)}')

    # Division estratificada (preserva proporciones de clase reales)
    sss = StratifiedShuffleSplit(n_splits=1, test_size=0.2, random_state=42)
    for train_idx, test_idx in sss.split(X, y):
        X_train, X_test = X[train_idx], X[test_idx]
        y_train, y_test = y[train_idx], y[test_idx]

    # Escalar datos con la media y desviacion estandar reales
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled  = scaler.transform(X_test)

    # Entrenar modelo GBT SIN pesos de clase (distribucion real del mercado)
    model = XGBClassifier(
        booster='gbtree',
        objective='multi:softprob',
        num_class=5,
        max_depth=6,
        learning_rate=0.1,
        n_estimators=200,
        subsample=0.8,
        colsample_bytree=0.8,
        reg_lambda=1.0,
        reg_alpha=0.5,
        random_state=42,
        verbosity=0
    )
    model.fit(X_train_scaled, y_train)
    y_pred = model.predict(X_test_scaled)
    acc = accuracy_score(y_test, y_pred)
    f1  = f1_score(y_test, y_pred, average='weighted')
    print(f'Test accuracy: {acc:.2%}')
    print(f'Weighted F1-score: {f1:.4f}')
    target_names = ['Strong Sell','Sell','Neutral','Buy','Strong Buy']
    print(classification_report(y_test, y_pred, target_names=target_names))

    if acc < 0.58 or f1 < 0.57:
        print('Quality thresholds not met. Model not saved.'); return False

    # Exportar ONNX
    initial_type = [('float_input', FloatTensorType([None, 12]))]
    onx = convert_xgboost(model, initial_types=initial_type, target_opset=12)
    onx = keep_only_probabilities(onx)
    with open(output_model, 'wb') as f:
        f.write(onx.SerializeToString())
    print(f'ONNX model saved: {output_model} ({os.path.getsize(output_model)} bytes)')

    # Guardar parametros de normalizacion (StandardScaler)
    norm_path = output_model.replace('.onnx', '.norm')
    with open(norm_path, 'wb') as f:
        for v in scaler.mean_:
            f.write(struct.pack('d', v))
        for v in scaler.scale_:
            f.write(struct.pack('d', v))
    print(f'Normalization params saved: {norm_path}')
    return True

def main():
    install_dependencies()
    parser = argparse.ArgumentParser()
    parser.add_argument('--csv', default=None); parser.add_argument('--output', default=None)
    args = parser.parse_args()
    if not train_and_export(args.csv, args.output): sys.exit(1)

if __name__ == '__main__':
    main()
