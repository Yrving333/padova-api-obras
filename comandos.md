# Comandos del proyecto api-obras

Referencia rápida, en el orden en que se usan. Reemplaza `<acr>`, `<rg>`, `<ca>` y `<kv>` con los valores de `terraform.tfvars` del repo de infra.

## Local

```powershell
python -m venv .venv; .\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
$env:MI_VARIABLE="local"; uvicorn app.main:app --port 8080
curl.exe http://localhost:8080/hello
```

## Docker local

```powershell
docker build --platform linux/amd64 --build-arg APP_VERSION=local -t api-obras:local .
docker images api-obras
docker run -d --name api-obras -p 8080:8080 -e MI_VARIABLE=docker api-obras:local
docker ps                               # esperar "(healthy)"
docker logs api-obras
docker rm -f api-obras
```

## Publicar en el ACR a mano (lo mismo que hace deploy.ps1)

```powershell
$tag = "$(git rev-parse --abbrev-ref HEAD)-$(git rev-parse --short HEAD)"
az acr login --name <acr>
docker build --platform linux/amd64 --build-arg APP_VERSION=$tag -t api-obras:$tag .
docker tag api-obras:$tag <acr>.azurecr.io/api-obras:$tag
docker push <acr>.azurecr.io/api-obras:$tag
az acr repository show-tags --name <acr> --repository api-obras -o table
```

## Desplegar

```powershell
.\scripts\deploy.ps1 -AcrName <acr> -SoloPublicar                         # primera vez
.\scripts\deploy.ps1 -AcrName <acr> -ResourceGroup <rg> -ContainerApp <ca> # nuevas versiones
.\scripts\deploy.ps1 -AcrName <acr> -ResourceGroup <rg> -ContainerApp <ca> -Multiplataforma  # extra amd64+arm64
```

## Verificar en Azure

```powershell
az containerapp revision list -n <ca> -g <rg> -o table
az containerapp logs show -n <ca> -g <rg> --follow
az containerapp show -n <ca> -g <rg> --query "properties.template.containers[0].image" -o tsv
az keyvault secret show --vault-name <kv> -n db-user --query value -o tsv
```

## Rotar un secreto

```powershell
az keyvault secret set --vault-name <kv> -n secreto-demo --value "nuevo-valor"   # /secreto lo lee al momento
# db-user / db-password se leen al arrancar: tras rotarlos, reiniciar la revision
az containerapp revision restart -n <ca> -g <rg> --revision (az containerapp revision list -n <ca> -g <rg> --query "[?properties.active].name | [0]" -o tsv)
```

## Volver a una versión anterior

```powershell
az containerapp update -n <ca> -g <rg> --image <acr>.azurecr.io/api-obras:<tag-anterior>
```
