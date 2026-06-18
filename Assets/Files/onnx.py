# create_onnx_12features.py
# Genera un modelo ONNX de 12 entradas y 2 salidas para Arion FX
# Salida: arion.onnx (entrada 12 features, salida 2 probabilidades)
# Uso: python create_onnx_12features.py

import os
import sys
import numpy as np
import onnx
from onnx import helper, TensorProto

np.random.seed(42)

print("Creando modelo ONNX para Arion FX (12 entradas → 2 salidas)...")

# Entrada: 12 características (5 SMC originales + 7 avanzadas)
X = helper.make_tensor_value_info('float_input', TensorProto.FLOAT, [1, 12])
# Salida: 2 probabilidades (alcista, bajista)
Y = helper.make_tensor_value_info('probabilities', TensorProto.FLOAT, [1, 2])

# Pesos aleatorios (2 x 12)
W = np.random.randn(2, 12).astype(np.float32)

# Inicializador de pesos (sin sesgo)
weight_init = helper.make_tensor('weight', TensorProto.FLOAT, [2, 12], W.flatten().tolist())

# Capa lineal (Gemm sin sesgo)
gemm_node = helper.make_node(
    'Gemm',
    inputs=['float_input', 'weight'],
    outputs=['logits'],
    alpha=1.0,
    beta=1.0,
    transB=1           # weight [2,12] * input [12,1] = [2,1]
)

# Softmax para obtener probabilidades
softmax_node = helper.make_node(
    'Softmax',
    inputs=['logits'],
    outputs=['probabilities'],
    axis=1
)

# Grafo
graph = helper.make_graph(
    [gemm_node, softmax_node],
    'ArionFX_12D_Model',
    [X],
    [Y],
    [weight_init]
)

# Opset 12 (requerido por MT5)
opset = onnx.OperatorSetIdProto()
opset.version = 12

model = helper.make_model(graph, opset_imports=[opset], producer_name='ArionFX')

# Guardar en la carpeta actual como arion.onnx
output_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'arion.onnx')
try:
    with open(output_path, 'wb') as f:
        f.write(model.SerializeToString())
    file_size = os.path.getsize(output_path)
    print(f"✅ Modelo guardado en: {output_path}")
    print(f"   Tamaño: {file_size} bytes")
    print("   Entrada: [1, 12] (12 características)")
    print("   Salida:  [1, 2] (probabilidad alcista, probabilidad bajista)")
    print("\n⚠️  Copia 'arion.onnx' a la carpeta 'Models' de tu experto:")
    print("   ...\\MQL5\\Experts\\Arion FX\\Models\\arion.onnx")
except Exception as e:
    print(f"❌ Error al guardar el modelo: {e}")
    sys.exit(1)