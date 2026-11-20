"""
api-obras - Microservicio de la Evaluacion Final IaC (DMC - Gestion de Infraestructura)
Contexto: catalogo de proyectos inmobiliarios de Grupo Padova.

Endpoints:
  /hello     -> saludo + nombre
  /variable  -> valor de una variable de entorno
  /secreto   -> secreto leido en tiempo de ejecucion desde Azure Key Vault (Managed Identity)
  /imagen    -> imagen descargada desde un Blob Storage (Managed Identity)
  /consulta  -> consulta a Azure SQL; usuario y password llegan como variables de entorno (desde Key Vault)
  /health    -> para probes y para el script de despliegue
"""
import logging
import os
from functools import lru_cache

from fastapi import FastAPI, HTTPException
from fastapi.responses import PlainTextResponse, Response

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("api-obras")

app = FastAPI(title="api-obras", version=os.getenv("APP_VERSION", "dev"))


def env(nombre: str, obligatoria: bool = True, defecto: str | None = None) -> str | None:
    valor = os.getenv(nombre, defecto)
    if obligatoria and not valor:
        # 500 con mensaje claro: ayuda a diagnosticar desde los logs (Application) del Container App
        raise HTTPException(status_code=500, detail=f"Falta la variable de entorno {nombre}")
    return valor


@lru_cache
def credencial():
    # En Azure usa la Managed Identity (AZURE_CLIENT_ID = client_id de la identity user-assigned).
    # En local usa tu sesion de "az login". Mismo codigo para ambos casos.
    from azure.identity import DefaultAzureCredential

    return DefaultAzureCredential()


@app.get("/", response_class=PlainTextResponse)
def raiz():
    return "api-obras OK. Endpoints: /hello /variable /secreto /imagen /consulta"


@app.get("/health")
def health():
    return {"status": "ok", "version": app.version}


@app.get("/hello", response_class=PlainTextResponse)
def hello():
    nombre = os.getenv("NOMBRE", "Yrving Leon")
    return f"Hola, bienvenido al microservicio de Grupo Padova. Soy {nombre}"


@app.get("/variable", response_class=PlainTextResponse)
def variable():
    valor = env("MI_VARIABLE")
    return f"Variable de entorno MI_VARIABLE: {valor}"


@app.get("/secreto", response_class=PlainTextResponse)
def secreto():
    from azure.keyvault.secrets import SecretClient

    vault_url = env("KEY_VAULT_URL")
    nombre_secreto = env("SECRET_NAME")
    try:
        cliente = SecretClient(vault_url=vault_url, credential=credencial())
        valor = cliente.get_secret(nombre_secreto).value
    except Exception as e:
        log.exception("Error leyendo Key Vault")
        raise HTTPException(status_code=502, detail=f"No se pudo leer el secreto: {type(e).__name__}")
    return f"Secreto '{nombre_secreto}' obtenido desde Key Vault: {valor}"


@app.get("/imagen")
def imagen():
    from azure.storage.blob import BlobClient

    blob = BlobClient(
        account_url=env("STORAGE_ACCOUNT_URL"),
        container_name=env("BLOB_CONTAINER"),
        blob_name=env("BLOB_NAME"),
        credential=credencial(),
    )
    try:
        descarga = blob.download_blob()
        contenido = descarga.readall()
        tipo = descarga.properties.content_settings.content_type or "image/jpeg"
    except Exception as e:
        log.exception("Error leyendo Blob Storage")
        raise HTTPException(status_code=502, detail=f"No se pudo leer la imagen: {type(e).__name__}")
    return Response(content=contenido, media_type=tipo)


@app.get("/consulta")
def consulta():
    import pymssql

    host = env("DB_HOST")
    try:
        # Azure SQL exige conexion cifrada (TLS): encryption="require"
        with pymssql.connect(
            server=host,
            port=env("DB_PORT", False, "1433"),
            user=env("DB_USER"),
            password=env("DB_PASSWORD"),
            database=env("DB_NAME"),
            encryption="require",
            login_timeout=15,
            timeout=15,
            as_dict=True,
        ) as conn, conn.cursor() as cur:
            cur.execute(
                "SELECT codigo, nombre, empresa, torres, departamentos, estado "
                "FROM dbo.proyectos ORDER BY codigo"
            )
            filas = cur.fetchall()
    except Exception as e:
        log.exception("Error consultando Azure SQL")
        raise HTTPException(status_code=502, detail=f"No se pudo consultar la BD: {type(e).__name__}")
    return {"origen": host, "total": len(filas), "proyectos": filas}
