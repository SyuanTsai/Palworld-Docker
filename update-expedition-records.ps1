[CmdletBinding()]
param(
    [string]$PlayerConfigPath
)

# Offline-only: do not add network calls or persist the decoded Level.sav JSON.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$repositoryRoot = $PSScriptRoot
if (-not $PlayerConfigPath) {
    $PlayerConfigPath = Join-Path $repositoryRoot 'expedition-player.local.json'
}
$guiDataRoot = Join-Path $repositoryRoot 'Data\GuiData'
$savedRoot = Join-Path $guiDataRoot 'instances\palworld-main\saved'
$saveGamesRoot = Join-Path $savedRoot 'SaveGames\0'
$parserRoot = Join-Path $guiDataRoot 'tools\palsav-palsav-tools-v1'
$parserPath = Join-Path $parserRoot 'palsav-linux-x64'
$checksumPath = Join-Path $parserRoot 'SHA256SUMS.txt'
$generatorPath = Join-Path $repositoryRoot 'BaseRecords\工具\產生遠征隊伍.mjs'
$palIndexPath = Join-Path $repositoryRoot 'BaseRecords\共用資料\配種資料\帕魯索引.csv'
$targetPath = Join-Path $repositoryRoot 'BaseRecords\共用資料\遠征隊伍配置.md'
$cacheRoot = Join-Path $guiDataRoot 'expedition-record-cache'
$cacheMarkdownPath = Join-Path $cacheRoot '遠征隊伍配置.md'
$serverContainer = 'Palworld-Server'
$managerContainer = 'Palworld-Manager'
$serverParserPath = '/tmp/palworld-expedition-records-palsav'
$managerGeneratorPath = '/tmp/palworld-expedition-records-generator.mjs'
$managerPalIndexPath = '/tmp/palworld-expedition-records-pal-index.csv'
$managerPlayerConfigPath = '/tmp/palworld-expedition-player.local.json'
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
        $detail = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        throw "$Step 失敗。$detail"
    }
    return @($output)
}

Assert-File -LiteralPath $PlayerConfigPath
Assert-File -LiteralPath $parserPath
Assert-File -LiteralPath $checksumPath
Assert-File -LiteralPath $generatorPath
Assert-File -LiteralPath $palIndexPath

try {
    $playerConfig = Get-Content -Raw -LiteralPath $PlayerConfigPath -Encoding UTF8 |
        ConvertFrom-Json
}
catch {
    throw "玩家設定檔不是有效的 JSON：$PlayerConfigPath"
}
if (-not $playerConfig.PlayerName -or -not $playerConfig.PlayerUId) {
    throw '玩家設定檔必須包含 PlayerName 與 PlayerUId。'
}
$playerName = $playerConfig.PlayerName.ToString().Trim()
$playerUid = $playerConfig.PlayerUId.ToString().Trim()
if (-not $playerName -or $playerUid -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
    throw '玩家設定檔的 PlayerName 或 PlayerUId 格式不正確。'
}

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

$temporaryName = '.expedition-records-' + [Guid]::NewGuid().ToString('N') + '.json'
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

try {
    Write-Host '正在解析目前 Level.sav 的玩家與帕魯資料（全程不連網）...'
    $null = Invoke-Docker -Arguments @(
        'exec', $serverContainer,
        $serverParserPath, 'convert', $serverSavePath,
        '--to-json',
        '--custom-properties', '.worldSaveData.CharacterSaveParameterMap.Value.RawData',
        '--output', $serverTemporaryPath,
        '--minify-json',
        '--force'
    ) -Step '解析 Level.sav'

    $null = Invoke-Docker -Arguments @('cp', $generatorPath, "${managerContainer}:$managerGeneratorPath") -Step '複製遠征摘要產生器'
    $null = Invoke-Docker -Arguments @('cp', $palIndexPath, "${managerContainer}:$managerPalIndexPath") -Step '複製帕魯名稱索引'
    $null = Invoke-Docker -Arguments @('cp', $PlayerConfigPath, "${managerContainer}:$managerPlayerConfigPath") -Step '複製本機玩家設定'

    $taipeiZone = [System.TimeZoneInfo]::FindSystemTimeZoneById('Taipei Standard Time')
    $snapshotLocal = [System.TimeZoneInfo]::ConvertTimeFromUtc($levelSave.LastWriteTimeUtc, $taipeiZone)
    $snapshotText = $snapshotLocal.ToString('yyyy-MM-dd HH:mm:ss')

    $null = Invoke-Docker -Arguments @(
        'exec', $managerContainer,
        'node', $managerGeneratorPath,
        $managerTemporaryPath,
        $managerPalIndexPath,
        $managerPlayerConfigPath,
        $managerCacheMarkdownPath,
        $snapshotText
    ) -Step '產生去識別化遠征摘要'

    Assert-File -LiteralPath $cacheMarkdownPath
    $privacyText = Get-Content -Raw -LiteralPath $cacheMarkdownPath -Encoding UTF8
    $forbiddenPatterns = @(
        '(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b'
        '(?i)\b(PlayerUId|OwnerPlayerUId|GuildName|group_id|token)\b'
        [Regex]::Escape($playerName)
    )
    foreach ($pattern in $forbiddenPatterns) {
        if ($privacyText -match $pattern) {
            throw '隱私檢查發現玩家或內部識別資料，未更新正式文件。'
        }
    }

    Copy-Item -LiteralPath $cacheMarkdownPath -Destination $targetPath -Force
}
finally {
    $null = & docker exec $managerContainer rm -f $managerPlayerConfigPath 2>$null
    if ($temporaryJsonPath -and (Test-Path -LiteralPath $temporaryJsonPath -PathType Leaf)) {
        $temporaryFull = [System.IO.Path]::GetFullPath($temporaryJsonPath)
        if ($temporaryFull.StartsWith($savedRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $temporaryFull -Force
        }
    }
}

$stopwatch.Stop()
Write-Host ("遠征隊伍資料已更新：{0}" -f $targetPath)
Write-Host ("完成時間：{0:N2} 秒；正式文件不含玩家名稱、玩家 ID 或個體 GUID。" -f $stopwatch.Elapsed.TotalSeconds)
