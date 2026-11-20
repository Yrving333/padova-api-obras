# api-obras — Microservicio Grupo Padova (Evaluación Final IaC)

Microservicio en **Python / FastAPI** que expone el catálogo de proyectos inmobiliarios de Grupo Padova (Sunny Park, Carabayllo 5, Litoral 900). Se empaqueta con Docker, se publica en **Azure Container Registry** y corre en **Azure Container Apps**. La infraestructura está en el repositorio `padova-api-obras-infra` (Terraform).

## Arquitectura

```
Usuario --HTTPS--> Container App (api-obras, 0..3 réplicas)
                     |-- imagen ----------> Azure Container Registry (AcrPull)
                     |-- /secreto --------> Key Vault (Key Vault Secrets User)
                     |-- /imagen ---------> Blob Storage (Storage Blob Data Reader)
                     '-- /consulta -------> Azure SQL (usuario/clave desde Key Vault)
```
Detalle completo en el README del repo `padova-api-obras-infra`.

## Endpoints

| Ruta | Qué devuelve | De dónde sale el dato |
|---|---|---|
| `/hello` | Saludo + nombre | Variable `NOMBRE` |
| `/variable` | `Variable de entorno MI_VARIABLE: <valor>` | Variable `MI_VARIABLE`, definida en Terraform |
| `/secreto` | Valor de un secreto | Azure Key Vault, leído en tiempo de ejecución con la Managed Identity |
| `/imagen` | Imagen JPG | Blob Storage privado, leído con la Managed Identity |
| `/consulta` | JSON con los proyectos | Azure SQL; host y base por variables, usuario y contraseña por variables que vienen de Key Vault |
| `/health` | `{"status":"ok","version":"<rama-commit>"}` | Probes de Azure, `HEALTHCHECK` de Docker y validación del despliegue |

Ninguna credencial está en el código ni en la imagen.

## Variables de entorno

| Variable | Uso |
|---|---|
| `NOMBRE`, `MI_VARIABLE` | `/hello`, `/variable` |
| `KEY_VAULT_URL`, `SECRET_NAME`, `AZURE_CLIENT_ID` | `/secreto` (identity user-assigned) |
| `STORAGE_ACCOUNT_URL`, `BLOB_CONTAINER`, `BLOB_NAME` | `/imagen` |
| `DB_HOST`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_PORT` (1433) | `/consulta` |
| `APP_VERSION` | La fija el build (`--build-arg`) con `rama-commit` |

## Estructura

```
app/main.py               código del microservicio
requirements.txt          dependencias con versión fija
Dockerfile                multi-stage, python:3.12-slim, COPY selectivo, usuario no root, HEALTHCHECK, puerto 8080
comandos.md               comandos del proyecto en el orden en que se usan
.dockerignore             deja fuera de la imagen lo que no es código
sql/seed.sql              tabla dbo.proyectos + datos (se ejecuta en el Query editor)
scripts/deploy.ps1        build -> tag rama-commit -> push al ACR -> az containerapp update -> valida
.github/workflows/ci.yml  CI: lint, prueba de endpoints, hadolint, docker build
docs/cicd.md              diagrama del flujo CI/CD
```

## Ejecutar en local

```powershell
python -m venv .venv; .\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
$env:MI_VARIABLE="local"; uvicorn app.main:app --port 8080
curl.exe http://localhost:8080/hello
```

## Docker en local

```powershell
docker build --platform linux/amd64 --build-arg APP_VERSION=local -t api-obras:local .
docker run -d --name api-obras -p 8080:8080 -e MI_VARIABLE=docker api-obras:local
docker ps          # STATUS debe pasar a "(healthy)"
curl.exe http://localhost:8080/hello
docker rm -f api-obras
```

## Publicar y desplegar

```powershell
# Primera vez (solo publicar en el ACR):
.\scripts\deploy.ps1 -AcrName acrapiobrasyldeveastus2001 -SoloPublicar

# Nuevas versiones (agrega -Multiplataforma para publicar amd64 + arm64):
.\scripts\deploy.ps1 -AcrName acrapiobrasyldeveastus2001 -ResourceGroup rg-apiobras-dev-eastus2-001 -ContainerApp ca-apiobras-dev-eastus2-001
```

El tag de la imagen es `<rama>-<commit corto>` (por ejemplo `main-a1b2c3d`). Cada versión desplegada se puede rastrear hasta su commit y volver a una anterior.

## CI/CD

Ver `docs/cicd.md`. En resumen:
- **CI:** se gatilla con cada Pull Request y cada push a `main` (GitHub Actions).
- **CD:** `deploy.ps1` publica la imagen en el ACR y despliega con `az containerapp update`.
