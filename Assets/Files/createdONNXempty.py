# createdONNXempty.py
# Genera un modelo ONNX de 5 clases compatible con Arion v1.0 (12D, sin sesgo)
# Salida: ArionIntelligence.onnx (entrada 12 features, salida 5 probabilidades)
# Uso: python createdONNXempty.py

import os, sys
import numpy as np
import onnx
from onnx import helper, TensorProto

np.random.seed(42)

print("Creando modelo ONNX 12D...")

# Entrada: 12 features
X = helper.make_tensor_value_info('float_input', TensorProto.FLOAT, [1, 12])
# Salida: 5 probabilidades
Y = helper.make_tensor_value_info('probabilities', TensorProto.FLOAT, [1, 5])

# Pesos aleatorios (12 -> 5)
W = np.random.randn(5, 12).astype(np.float32)

# Inicializador de pesos (sin sesgo)
weight_init = helper.make_tensor('weight', TensorProto.FLOAT, [5, 12], W.flatten().tolist())

# Nodo Gemm sin bias
gemm_node = helper.make_node(
    'Gemm',
    inputs=['float_input', 'weight'],
    outputs=['logits'],
    alpha=1.0,
    beta=1.0,
    transB=1
)

# Nodo Softmax
softmax_node = helper.make_node(
    'Softmax',
    inputs=['logits'],
    outputs=['probabilities'],
    axis=1
)

# Grafo
graph = helper.make_graph(
    [gemm_node, softmax_node],
    'Arion12DModel',
    [X],
    [Y],
    [weight_init]
)

# Opset 12 (MT5)
opset = onnx.OperatorSetIdProto()
opset.version = 12

model = helper.make_model(graph, opset_imports=[opset], producer_name='Arion')

# Guardar en la carpeta donde se ejecuta el script
output_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'ArionIntelligence.onnx')
try:
    with open(output_path, 'wb') as f:
        f.write(model.SerializeToString())
    file_size = os.path.getsize(output_path)
    print(f"✅ Modelo guardado en: {output_path}")
    print(f"   Tamaño: {file_size} bytes")
    print("   Entrada: [1,12]  Salida: [1,5] (sin sesgo)")
except Exception as e:
    print(f"❌ Error al guardar el modelo: {e}")
    sys.exit(1)