[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$StorageAccountName,

    [Parameter(Mandatory = $true)]
    [string]$SourceDirectory,

    [string]$ContainerName = "recordings"
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path -Path $SourceDirectory -PathType Container)) {
    throw "Source directory does not exist: $SourceDirectory"
}

az storage blob upload-batch `
    --account-name $StorageAccountName `
    --auth-mode login `
    --destination $ContainerName `
    --source $SourceDirectory `
    --overwrite false
if ($LASTEXITCODE -ne 0) { throw "Recording upload failed." }

Write-Host "Upload complete. Each new blob will start one durable orchestration."