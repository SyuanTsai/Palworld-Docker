[CmdletBinding()]
param(
    [int]$WorkerLimit = 30,
    [switch]$ForceRefresh
)

# Offline-only: do not add network calls or persist the decoded Level.sav JSON.
# Use update-base-records.cmd to bypass the local PowerShell execution policy.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$repositoryRoot = $PSScriptRoot
$guiDataRoot = Join-Path $repositoryRoot 'Data\GuiData'
$savedRoot = Join-Path $guiDataRoot 'instances\palworld-main\saved'
$saveGamesRoot = Join-Path $savedRoot 'SaveGames\0'
$parserRoot = Join-Path $guiDataRoot 'tools\palsav-palsav-tools-v1'
$parserPath = Join-Path $parserRoot 'palsav-linux-x64'
$checksumPath = Join-Path $parserRoot 'SHA256SUMS.txt'
$generatorPath = Join-Path $repositoryRoot 'BaseRecords\工具\產生據點現況.mjs'
$palIndexPath = Join-Path $repositoryRoot 'BaseRecords\共用資料\配種資料\帕魯索引.csv'
$targetPath = Join-Path $repositoryRoot 'BaseRecords\共用資料\據點存檔現況.md'
$cacheRoot = Join-Path $guiDataRoot 'base-record-cache'
$cacheMarkdownPath = Join-Path $cacheRoot '據點存檔現況.md'
$cacheMetadataPath = Join-Path $cacheRoot 'metadata.json'
$serverContainer = 'Palworld-Server'
$managerContainer = 'Palworld-Manager'
$serverParserPath = '/tmp/palworld-base-records-palsav'
$managerGeneratorPath = '/tmp/palworld-base-records-generator.mjs'
$managerPalIndexPath = '/tmp/palworld-base-records-pal-index.csv'
$temporaryJsonPath = $null

function Assert-File {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        throw "找不到必要檔案：$LiteralPath"
    }
}

function Convert-ToDockerDesktopPath {
    param([Parameter(Mandatory = $true)][string]$WindowsPath)
    $fullPath = [System.IO.Path]::GetFullPath($WindowsPath)
    if ($fullPath -notmatch '^([A-Za-z]):\\(.*)$') {
        throw '只能轉換 Windows 磁碟機的絕對路徑。'
    }
    $drive = $Matches[1].ToLowerInvariant()
    $tail = $Matches[2].Replace('\', '/')
    return "/run/desktop/mnt/host/$drive/$tail"
}

function Invoke-Docker {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Step
    )
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & docker @Arguments 2>&1
        $dockerExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }
    if ($dockerExitCode -ne 0) {
        throw "$Step 失敗。請確認 Docker Desktop 與 Palworld 容器均在執行。"
    }
    return @($output)
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][string]$Content
    )
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($LiteralPath, $Content, $encoding)
}

if ($WorkerLimit -lt 1) {
    throw 'WorkerLimit 必須大於 0。'
}

Assert-File -LiteralPath $parserPath
Assert-File -LiteralPath $checksumPath
Assert-File -LiteralPath $generatorPath
Assert-File -LiteralPath $palIndexPath

$checksumLine = Get-Content -LiteralPath $checksumPath |
    Where-Object { $_ -match '\spalsav-linux-x64$' } |
    Select-Object -First 1
if (-not $checksumLine) {
    throw 'SHA256SUMS.txt 沒有 palsav-linux-x64 的雜湊。'
}
$expectedParserHash = ($checksumLine -split '\s+')[0].ToUpperInvariant()
$actualParserHash = (Get-FileHash -LiteralPath $parserPath -Algorithm SHA256).Hash
if ($actualParserHash -ne $expectedParserHash) {
    throw '存檔解析器雜湊不符，為避免執行遭竄改的程式，已停止更新。'
}

$levelSave = Get-ChildItem -LiteralPath $saveGamesRoot -Filter 'Level.sav' -File -Recurse |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1
if (-not $levelSave) {
    throw '找不到 Palworld Level.sav。'
}

$sourceHash = (Get-FileHash -LiteralPath $levelSave.FullName -Algorithm SHA256).Hash
$metadata = $null
if (Test-Path -LiteralPath $cacheMetadataPath -PathType Leaf) {
    try {
        $metadata = Get-Content -Raw -LiteralPath $cacheMetadataPath -Encoding UTF8 |
            ConvertFrom-Json
    }
    catch {
        $metadata = $null
    }
}

$cacheHit = -not $ForceRefresh.IsPresent -and
    $metadata -and
    $metadata.Schema -eq 1 -and
    $metadata.SourceSha256 -eq $sourceHash -and
    $metadata.WorkerLimit -eq $WorkerLimit -and
    (Test-Path -LiteralPath $cacheMarkdownPath -PathType Leaf)

if ($cacheHit) {
    Copy-Item -LiteralPath $cacheMarkdownPath -Destination $targetPath -Force
    $stopwatch.Stop()
    Write-Host ("據點資料沒有變更，已使用去識別化快取更新：{0:N2} 秒" -f $stopwatch.Elapsed.TotalSeconds)
    return
}

New-Item -ItemType Directory -Path $cacheRoot -Force | Out-Null

$null = Invoke-Docker -Arguments @('version', '--format', '{{.Server.Version}}') -Step '連線本機 Docker'
foreach ($container in @($serverContainer, $managerContainer)) {
    $running = Invoke-Docker -Arguments @('inspect', '--format', '{{.State.Running}}', $container) -Step "檢查 $container"
    if (($running | Select-Object -Last 1).ToString().Trim() -ne 'true') {
        throw "$container 尚未執行。"
    }
}

$null = & docker exec $serverContainer test -x $serverParserPath 2>$null
if ($LASTEXITCODE -ne 0) {
    $null = Invoke-Docker -Arguments @('cp', $parserPath, "${serverContainer}:$serverParserPath") -Step '複製存檔解析器'
    $null = Invoke-Docker -Arguments @('exec', $serverContainer, 'chmod', '700', $serverParserPath) -Step '設定解析器權限'
}

$temporaryName = '.base-records-' + [Guid]::NewGuid().ToString('N') + '.json'
$temporaryJsonPath = Join-Path $savedRoot $temporaryName
$savedRootFull = [System.IO.Path]::GetFullPath($savedRoot).TrimEnd('\') + '\'
$temporaryFull = [System.IO.Path]::GetFullPath($temporaryJsonPath)
if (-not $temporaryFull.StartsWith($savedRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw '暫存檔路徑不在預期的存檔目錄內。'
}

$relativeSavePath = $levelSave.FullName.Substring($savedRootFull.Length).Replace('\', '/')
$serverSavePath = '/data/saved/' + $relativeSavePath
$serverTemporaryPath = '/data/saved/' + $temporaryName
$managerTemporaryPath = Convert-ToDockerDesktopPath -WindowsPath $temporaryJsonPath
$managerCacheMarkdownPath = Convert-ToDockerDesktopPath -WindowsPath $cacheMarkdownPath

$customProperties = @(
    '.worldSaveData.CharacterSaveParameterMap.Value.RawData'
    '.worldSaveData.CharacterContainerSaveData.Value.Slots.Slots.RawData'
    '.worldSaveData.BaseCampSaveData.Value.RawData'
    '.worldSaveData.BaseCampSaveData.Value.WorkerDirector.RawData'
    '.worldSaveData.WorkSaveData'
    '.worldSaveData.MapObjectSaveData'
) -join ','

try {
    Write-Host '存檔有變更，正在本機解析並去識別化（不會上傳）...'
    $null = Invoke-Docker -Arguments @(
        'exec', $serverContainer,
        $serverParserPath, 'convert', $serverSavePath,
        '--to-json',
        '--custom-properties', $customProperties,
        '--output', $serverTemporaryPath,
        '--minify-json',
        '--force'
    ) -Step '解析 Level.sav'

    $null = Invoke-Docker -Arguments @('cp', $generatorPath, "${managerContainer}:$managerGeneratorPath") -Step '複製本機摘要產生器'
    $null = Invoke-Docker -Arguments @('cp', $palIndexPath, "${managerContainer}:$managerPalIndexPath") -Step '複製帕魯名稱索引'

    $taipeiZone = [System.TimeZoneInfo]::FindSystemTimeZoneById('Taipei Standard Time')
    $snapshotLocal = [System.TimeZoneInfo]::ConvertTimeFromUtc($levelSave.LastWriteTimeUtc, $taipeiZone)
    $snapshotText = $snapshotLocal.ToString('yyyy-MM-dd HH:mm:ss')

    $null = Invoke-Docker -Arguments @(
        'exec', $managerContainer,
        'node', $managerGeneratorPath,
        $managerTemporaryPath,
        $managerPalIndexPath,
        $managerCacheMarkdownPath,
        $snapshotText,
        $WorkerLimit.ToString()
    ) -Step '產生去識別化據點摘要'

    Assert-File -LiteralPath $cacheMarkdownPath
    $privacyText = Get-Content -Raw -LiteralPath $cacheMarkdownPath -Encoding UTF8
    $forbiddenPatterns = @(
        '(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b'
        '(?i)\b(PlayerUId|OwnerPlayerUId|GuildName|group_id|build_player_uid|token)\b'
        '\b\d{15,20}\b'
    )
    foreach ($pattern in $forbiddenPatterns) {
        if ($privacyText -match $pattern) {
            throw '隱私檢查發現可能的玩家、公會或內部識別資料，未更新正式文件。'
        }
    }

    Copy-Item -LiteralPath $cacheMarkdownPath -Destination $targetPath -Force
    $metadataObject = [ordered]@{
        Schema = 1
        SourceSha256 = $sourceHash
        WorkerLimit = $WorkerLimit
        SnapshotTime = $snapshotText
    }
    Write-Utf8NoBom -LiteralPath $cacheMetadataPath -Content ($metadataObject | ConvertTo-Json)
}
finally {
    if ($temporaryJsonPath -and (Test-Path -LiteralPath $temporaryJsonPath -PathType Leaf)) {
        $temporaryFull = [System.IO.Path]::GetFullPath($temporaryJsonPath)
        if ($temporaryFull.StartsWith($savedRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $temporaryFull -Force
        }
    }
}

$stopwatch.Stop()
Write-Host ("01～05 據點資料已更新：{0}" -f $targetPath)
Write-Host ("完成時間：{0:N2} 秒；快取中只保留去識別化 Markdown 與本機雜湊。" -f $stopwatch.Elapsed.TotalSeconds)
