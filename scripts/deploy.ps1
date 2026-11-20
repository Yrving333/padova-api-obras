<#
  deploy.ps1 - Flujo Docker completo (requisito 5 de la Evaluacion Final)
  Toma el codigo -> genera una nueva version de la imagen (tag = rama-commit) -> push al ACR
  -> despliega la nueva version en Azure Container Apps (az cli) -> valida.

  Uso normal (nueva version):
    .\scripts\deploy.ps1 -AcrName acrapiobrasyldeveus2001 -ResourceGroup rg-apiobras-dev-eastus2-001 -ContainerApp ca-apiobras-dev-eastus2-001

  Primera vez (el Container App aun no existe): solo construir y publicar
    .\scripts\deploy.ps1 -AcrName acrapiobrasyldeveus2001 -SoloPublicar

  Requisitos: Docker Desktop abierto, az login hecho, rol AcrPush/Owner sobre el ACR.
  Si PowerShell bloquea el script: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
#>
param(
    [Parameter(Mandatory = $true)] [string] $AcrName,
    [string] $ResourceGroup,
    [string] $ContainerApp,
    [string] $ImageName = "api-obras",
    [switch] $SoloPublicar,
    # Extra: publica una sola imagen para linux/amd64 (Azure) y linux/arm64 (Mac Apple Silicon)
    [switch] $Multiplataforma
)

$ErrorActionPreference = "Stop"

function Paso($texto) { Write-Host "`n==> $texto" -ForegroundColor Cyan }
function Verificar($descripcion) {
    if ($LASTEXITCODE -ne 0) { Write-Host "ERROR en: $descripcion" -ForegroundColor Red; exit 1 }
}

if (-not $SoloPublicar -and (-not $ResourceGroup -or -not $ContainerApp)) {
    Write-Host "Falta -ResourceGroup y -ContainerApp (o usa -SoloPublicar)." -ForegroundColor Red; exit 1
}

# 1. Tag = rama + id corto del commit (recomendacion del profesor; nunca 'latest')
Paso "Calculando la version a partir de Git"
if (git status --porcelain) {
    Write-Host "Hay cambios sin commit. Haz commit antes de desplegar para que el tag sea trazable." -ForegroundColor Yellow
    exit 1
}
$rama   = (git rev-parse --abbrev-ref HEAD).Trim() -replace '[^a-zA-Z0-9_.-]', '-'; Verificar "git rev-parse rama"
$commit = (git rev-parse --short HEAD).Trim(); Verificar "git rev-parse commit"
$tag    = "$rama-$commit"
$loginServer = "$AcrName.azurecr.io"
$imagen = "$loginServer/${ImageName}:$tag"
Write-Host "Imagen: $imagen"

# 2. Login al ACR (usa tu sesion de az login, sin usuario admin)
Paso "az acr login"
az acr login --name $AcrName; Verificar "az acr login"

if ($Multiplataforma) {
    # 3a. Build multiplataforma con buildx: construye y publica amd64 + arm64 en un solo paso
    Paso "docker buildx build (linux/amd64, linux/arm64) + push"
    docker buildx inspect padova-multi *> $null
    if ($LASTEXITCODE -ne 0) { docker buildx create --name padova-multi --use | Out-Null } else { docker buildx use padova-multi }
    docker buildx build --platform linux/amd64,linux/arm64 --build-arg APP_VERSION=$tag -t $imagen --push .
    Verificar "docker buildx build"
    docker buildx imagetools inspect $imagen
} else {
    # 3b. Build para la arquitectura de Azure (linux/amd64) + tag + push
    Paso "docker build + tag + push"
    docker build --platform linux/amd64 --build-arg APP_VERSION=$tag -t "${ImageName}:$tag" .; Verificar "docker build"
    docker images $ImageName
    docker tag "${ImageName}:$tag" $imagen; Verificar "docker tag"
    docker push $imagen; Verificar "docker push"
}
az acr repository show-tags --name $AcrName --repository $ImageName --orderby time_desc --top 5 -o table

if ($SoloPublicar) {
    Write-Host "`nImagen publicada. Pon este valor en terraform.tfvars:" -ForegroundColor Green
    Write-Host "imagen_tag = `"$tag`"" -ForegroundColor Green
    exit 0
}

# 4. Despliegue: nueva revision del Container App con la nueva imagen
Paso "az containerapp update"
az containerapp update --name $ContainerApp --resource-group $ResourceGroup --image $imagen --output none
Verificar "az containerapp update"

# 5. Validacion
Paso "Validando despliegue"
$fqdn = az containerapp show -n $ContainerApp -g $ResourceGroup --query "properties.configuration.ingress.fqdn" -o tsv
$url = "https://$fqdn"
$ok = $false
for ($i = 1; $i -le 18; $i++) {
    try {
        $r = Invoke-RestMethod "$url/health" -TimeoutSec 15
        if ($r.version -eq $tag) { $ok = $true; break }
        Write-Host "Responde la version $($r.version); esperando $tag ($i/18)..."
    } catch { Write-Host "Esperando la nueva revision ($i/18)..." }
    Start-Sleep -Seconds 10
}
az containerapp revision list -n $ContainerApp -g $ResourceGroup `
    --query "[].{revision:name, activa:properties.active, estado:properties.runningState, trafico:properties.trafficWeight, imagen:properties.template.containers[0].image}" -o table
if (-not $ok) { Write-Host "La nueva version no respondio a tiempo. Revisa Log stream del Container App." -ForegroundColor Red; exit 1 }

foreach ($p in @("hello", "variable", "secreto", "consulta")) {
    Write-Host "`nGET $url/$p" -ForegroundColor Green
    try { Invoke-RestMethod "$url/$p" -TimeoutSec 30 | ConvertTo-Json -Depth 5 | Write-Host }
    catch { Write-Host "Fallo: $($_.Exception.Message)" -ForegroundColor Red }
}
Write-Host "`nImagen: abre $url/imagen en el navegador" -ForegroundColor Green
Write-Host "Desplegado: $imagen" -ForegroundColor Cyan
