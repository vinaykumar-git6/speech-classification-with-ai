[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [string]$ResourceGroupName = "rg-audio-intelligence-dev",

    [string]$Location = "swedencentral",

    [switch]$Apply
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$template = Join-Path $root "infra/main.bicep"
$parameters = Join-Path $root "infra/main.parameters.json"

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI is required. Install it and run 'az login' before continuing."
}

az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) { throw "Unable to select Azure subscription $SubscriptionId." }

$groupExists = az group exists --name $ResourceGroupName | ConvertFrom-Json
if (-not $groupExists) {
    if (-not $Apply) {
        throw "Resource group $ResourceGroupName does not exist. Re-run with -Apply to create it."
    }
    az group create --name $ResourceGroupName --location $Location --output none
    if ($LASTEXITCODE -ne 0) { throw "Resource group creation failed." }
}

az deployment group validate `
    --resource-group $ResourceGroupName `
    --template-file $template `
    --parameters "@$parameters" location=$Location `
    --output none
if ($LASTEXITCODE -ne 0) { throw "ARM validation failed." }

az deployment group what-if `
    --resource-group $ResourceGroupName `
    --template-file $template `
    --parameters "@$parameters" location=$Location
if ($LASTEXITCODE -ne 0) { throw "ARM what-if failed." }

if (-not $Apply) {
    Write-Host "Validation and what-if succeeded. Re-run with -Apply to deploy."
    exit 0
}

$deployment = az deployment group create `
    --name "audio-intelligence-$((Get-Date).ToString('yyyyMMddHHmmss'))" `
    --resource-group $ResourceGroupName `
    --template-file $template `
    --parameters "@$parameters" location=$Location `
    --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw "Infrastructure deployment failed." }

$functionAppName = $deployment.properties.outputs.functionAppName.value
if (-not (Get-Command func -ErrorAction SilentlyContinue)) {
    throw "Infrastructure deployed. Install Azure Functions Core Tools, then publish to $functionAppName."
}

Push-Location $root
try {
    func azure functionapp publish $functionAppName --python
    if ($LASTEXITCODE -ne 0) { throw "Function application publish failed." }
}
finally {
    Pop-Location
}

Write-Host "Deployment complete. Function app: $functionAppName"