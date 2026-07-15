param(
    [string]$Tag = "latest",
    [switch]$PruneAllUnusedImages
)

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ComposeDir = Join-Path $RootDir "compose"
$ComposeFile = Join-Path $ComposeDir "compose.yaml"
$ServiceName = "palworld-server"
$ContainerName = "Palworld-Server"
$Image = "ghcr.io/pocketpairjp/palserver:$Tag"

if (-not (Test-Path -LiteralPath $ComposeFile)) {
    throw "Cannot find compose file: $ComposeFile"
}

Write-Host "Updating compose image to $Image"
$compose = Get-Content -LiteralPath $ComposeFile -Raw
$compose = $compose -replace "ghcr\.io/pocketpairjp/palserver:(latest|v[0-9.]+)", $Image
Set-Content -LiteralPath $ComposeFile -Value $compose -NoNewline

Write-Host "Pulling image..."
docker compose -f $ComposeFile pull $ServiceName

Write-Host "Recreating server..."
docker compose -f $ComposeFile up -d --force-recreate

Write-Host "Cleaning up old Docker images..."
if ($PruneAllUnusedImages) {
    Write-Host "Pruning all unused images, including tagged images that no container uses."
    docker image prune -a -f
} else {
    Write-Host "Pruning dangling images only, such as <none>:<none> images left after updates."
    docker image prune -f
}

Write-Host "Current server status:"
docker compose -f $ComposeFile ps

Write-Host "Docker disk usage:"
docker system df

Write-Host "Recent logs:"
docker logs $ContainerName --tail 60
