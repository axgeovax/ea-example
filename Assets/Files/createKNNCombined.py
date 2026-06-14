import os
import pandas as pd

# Columnas requeridas para el nuevo estándar 12D
FEATURE_COLS = [
    'slope', 'atr', 'momentum', 'volFlow', 'adx', 'rsi',
    'deltaVol', 'spreadDev', 'smcRatio', 'relStrength',
    'normVolatility', 'volRatio'
]
REQUIRED_COLS = FEATURE_COLS + ['direction', 'time']


def combine_knn_files():
    # Carpeta donde está este script
    base = os.path.dirname(os.path.abspath(__file__))

    # Buscar todos los archivos que terminen en _KNN.csv
    files = [f for f in os.listdir(base) if f.endswith("_KNN.csv")]

    print("Archivos detectados:")
    for f in files:
        print(" -", f)

    if not files:
        print("❌ No se encontraron archivos *_KNN.csv en esta carpeta.")
        return

    df_list = []
    for f in files:
        try:
            df = pd.read_csv(os.path.join(base, f))

            # Validar columnas
            missing = [col for col in REQUIRED_COLS if col not in df.columns]
            if missing:
                print(f"⚠️ {f} no contiene las columnas requeridas ({missing}). Se omitirá.")
                continue

            # Eliminar líneas de estadísticas si existen
            df = df[~df['slope'].astype(str).str.startswith('#')]
            df_list.append(df)
            print(f"✔ {f}: {len(df)} muestras válidas")

        except Exception as e:
            print(f"⚠️ Error leyendo {f}: {e}")

    if not df_list:
        print("❌ No se pudo cargar ningún archivo CSV válido.")
        return

    # Combinar todo
    df_combined = pd.concat(df_list, ignore_index=True)

    # Guardar archivo final (KNN.csv en la misma carpeta)
    output_file = os.path.join(base, "KNN.csv")
    df_combined.to_csv(output_file, index=False)

    print("\n✔ Archivo combinado generado:")
    print(output_file)
    print(f"Total de muestras: {len(df_combined)}")
    print(f"Columnas: {list(df_combined.columns)}")


if __name__ == "__main__":
    combine_knn_files()