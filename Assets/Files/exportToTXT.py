import os

def main():
    carpeta = os.path.dirname(os.path.abspath(__file__))
    carpeta_txt = os.path.join(carpeta, "txt")

    # Crear carpeta txt si no existe
    if not os.path.exists(carpeta_txt):
        os.makedirs(carpeta_txt)

    for nombre in os.listdir(carpeta):
        ruta = os.path.join(carpeta, nombre)

        # Ignorar carpetas y el propio script
        if os.path.isdir(ruta) or nombre.endswith(".py"):
            continue

        # Crear nombre del archivo txt dentro de /txt
        nombre_txt = nombre + ".txt"
        ruta_txt = os.path.join(carpeta_txt, nombre_txt)

        try:
            with open(ruta, "rb") as original:
                contenido = original.read()

            with open(ruta_txt, "wb") as copia:
                copia.write(contenido)

            print(f"✔ Copiado: {nombre} → txt/{nombre_txt}")

        except Exception as e:
            print(f"⚠ Error copiando {nombre}: {e}")

if __name__ == "__main__":
    main()
