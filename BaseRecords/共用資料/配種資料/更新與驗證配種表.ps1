[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceDirectory = Join-Path $PSScriptRoot '來源'
$databasePath = Join-Path $sourceDirectory 'palcalc-db-v26.json'
$breedingPath = Join-Path $sourceDirectory 'palcalc-breeding-v26.json'
$palIndexPath = Join-Path $PSScriptRoot '帕魯索引.csv'
$breedingTablePath = Join-Path $PSScriptRoot '完整配種表.csv'

$expectedDatabaseHash = '803d891afdb18bd00e24332844a7276bbe5c0855170ef90ef142f2f4d7698ed1'
$expectedBreedingHash = '1af1e4d6b461599ec3b80a2195002337ff484ed3c28ce57e27def96138262ec2'
$expectedPalCount = 299
$expectedBreedingCount = 44851
$expectedPairCount = 44850

function Get-LowercaseSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function ConvertTo-CsvField {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return '""'
    }

    return '"' + ([string]$Value).Replace('"', '""') + '"'
}

function Write-Utf8BomCsv {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Headers,
        [Parameter(Mandatory = $true)][System.Collections.IEnumerable]$Rows
    )

    $utf8WithBom = New-Object System.Text.UTF8Encoding($true)
    $writer = New-Object System.IO.StreamWriter($Path, $false, $utf8WithBom)
    try {
        $writer.WriteLine((($Headers | ForEach-Object { ConvertTo-CsvField $_ }) -join ','))
        foreach ($row in $Rows) {
            $values = foreach ($header in $Headers) {
                ConvertTo-CsvField $row.$header
            }
            $writer.WriteLine(($values -join ','))
        }
    }
    finally {
        $writer.Dispose()
    }
}

foreach ($requiredPath in @($databasePath, $breedingPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "缺少來源檔：$requiredPath"
    }
}

$databaseHash = Get-LowercaseSha256 $databasePath
$breedingHash = Get-LowercaseSha256 $breedingPath

if ($databaseHash -ne $expectedDatabaseHash) {
    throw "資料庫來源檔 SHA-256 不符。預期：$expectedDatabaseHash；實際：$databaseHash"
}
if ($breedingHash -ne $expectedBreedingHash) {
    throw "配種來源檔 SHA-256 不符。預期：$expectedBreedingHash；實際：$breedingHash"
}

$database = [System.IO.File]::ReadAllText($databasePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$breedingDatabase = [System.IO.File]::ReadAllText($breedingPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json

if ($database.Version -ne 'v26') {
    throw "資料庫版本不是 v26：$($database.Version)"
}
if ($database.Pals.Count -ne $expectedPalCount) {
    throw "帕魯數量不符。預期：$expectedPalCount；實際：$($database.Pals.Count)"
}
if ($breedingDatabase.Breeding.Count -ne $expectedBreedingCount) {
    throw "配種列數不符。預期：$expectedBreedingCount；實際：$($breedingDatabase.Breeding.Count)"
}

$palByInternalName = @{}
foreach ($pal in $database.Pals) {
    if ($palByInternalName.ContainsKey($pal.InternalName)) {
        throw "重複的帕魯內部名稱：$($pal.InternalName)"
    }
    if ([string]::IsNullOrWhiteSpace($pal.LocalizedNames.'zh-Hant')) {
        throw "缺少繁中名稱：$($pal.InternalName)"
    }
    $palByInternalName[$pal.InternalName] = $pal
}

$pairKeys = New-Object 'System.Collections.Generic.HashSet[string]'
$exactRows = New-Object 'System.Collections.Generic.HashSet[string]'
$genderDirectedCount = 0
$sameSpeciesCount = 0

foreach ($row in $breedingDatabase.Breeding) {
    foreach ($internalName in @($row.Parent1InternalName, $row.Parent2InternalName, $row.ChildInternalName)) {
        if (-not $palByInternalName.ContainsKey($internalName)) {
            throw "配種資料引用不存在的帕魯：$internalName"
        }
    }

    $parentNames = @($row.Parent1InternalName, $row.Parent2InternalName) | Sort-Object
    [void]$pairKeys.Add(($parentNames -join '|'))

    $exactKey = @(
        $row.Parent1InternalName,
        $row.Parent1Gender,
        $row.Parent2InternalName,
        $row.Parent2Gender,
        $row.ChildInternalName
    ) -join '|'
    if (-not $exactRows.Add($exactKey)) {
        throw "發現完全重複的配種列：$exactKey"
    }

    if ($row.Parent1Gender -ne 'WILDCARD' -or $row.Parent2Gender -ne 'WILDCARD') {
        $genderDirectedCount++
    }
    if ($row.Parent1InternalName -eq $row.Parent2InternalName) {
        $sameSpeciesCount++
    }
}

if ($pairKeys.Count -ne $expectedPairCount) {
    throw "未完整覆蓋所有不分順序的親代組合。預期：$expectedPairCount；實際：$($pairKeys.Count)"
}
if ($sameSpeciesCount -ne $expectedPalCount) {
    throw "同種配種列數不符。預期：$expectedPalCount；實際：$sameSpeciesCount"
}
if ($genderDirectedCount -ne 2) {
    throw "性別限定列數不符。預期：2；實際：$genderDirectedCount"
}

$palHeaders = @(
    '圖鑑編號',
    '亞種',
    '繁中名稱',
    '英文名稱',
    '內部名稱',
    '配種值',
    '配種優先值'
)

$palRows = $database.Pals |
    Sort-Object @{ Expression = { [int]$_.Id.PalDexNo } }, @{ Expression = { [bool]$_.Id.IsVariant } }, InternalName |
    ForEach-Object {
        [pscustomobject][ordered]@{
            '圖鑑編號' = $_.Id.PalDexNo
            '亞種' = if ($_.Id.IsVariant) { '是' } else { '否' }
            '繁中名稱' = $_.LocalizedNames.'zh-Hant'
            '英文名稱' = $_.LocalizedNames.en
            '內部名稱' = $_.InternalName
            '配種值' = $_.BreedingPower
            '配種優先值' = $_.BreedingPowerPriority
        }
    }

$genderNames = @{
    'WILDCARD' = '任一'
    'MALE' = '雄性'
    'FEMALE' = '雌性'
}

$breedingHeaders = @(
    '親代1圖鑑編號',
    '親代1繁中',
    '親代1英文',
    '親代1內部名稱',
    '親代1性別',
    '親代2圖鑑編號',
    '親代2繁中',
    '親代2英文',
    '親代2內部名稱',
    '親代2性別',
    '子代圖鑑編號',
    '子代繁中',
    '子代英文',
    '子代內部名稱',
    '性別限定'
)

$breedingRows = $breedingDatabase.Breeding |
    ForEach-Object {
        $parent1 = $palByInternalName[$_.Parent1InternalName]
        $parent2 = $palByInternalName[$_.Parent2InternalName]
        $child = $palByInternalName[$_.ChildInternalName]
        $isGenderDirected = $_.Parent1Gender -ne 'WILDCARD' -or $_.Parent2Gender -ne 'WILDCARD'

        [pscustomobject][ordered]@{
            '親代1圖鑑編號' = $parent1.Id.PalDexNo
            '親代1繁中' = $parent1.LocalizedNames.'zh-Hant'
            '親代1英文' = $parent1.LocalizedNames.en
            '親代1內部名稱' = $parent1.InternalName
            '親代1性別' = $genderNames[$_.Parent1Gender]
            '親代2圖鑑編號' = $parent2.Id.PalDexNo
            '親代2繁中' = $parent2.LocalizedNames.'zh-Hant'
            '親代2英文' = $parent2.LocalizedNames.en
            '親代2內部名稱' = $parent2.InternalName
            '親代2性別' = $genderNames[$_.Parent2Gender]
            '子代圖鑑編號' = $child.Id.PalDexNo
            '子代繁中' = $child.LocalizedNames.'zh-Hant'
            '子代英文' = $child.LocalizedNames.en
            '子代內部名稱' = $child.InternalName
            '性別限定' = if ($isGenderDirected) { '是' } else { '否' }
        }
    } |
    Sort-Object '子代繁中', '親代1繁中', '親代2繁中', '親代1性別', '親代2性別'

Write-Utf8BomCsv -Path $palIndexPath -Headers $palHeaders -Rows $palRows
Write-Utf8BomCsv -Path $breedingTablePath -Headers $breedingHeaders -Rows $breedingRows

$generatedPalCount = (Import-Csv -LiteralPath $palIndexPath -Encoding UTF8).Count
$generatedBreedingCount = (Import-Csv -LiteralPath $breedingTablePath -Encoding UTF8).Count

if ($generatedPalCount -ne $expectedPalCount) {
    throw "產出的帕魯索引列數不符：$generatedPalCount"
}
if ($generatedBreedingCount -ne $expectedBreedingCount) {
    throw "產出的完整配種表列數不符：$generatedBreedingCount"
}

Write-Output '配種資料已通過驗證並重新產生。'
Write-Output "資料庫版本：$($database.Version)"
Write-Output "帕魯索引：$generatedPalCount 列"
Write-Output "完整配種表：$generatedBreedingCount 列"
Write-Output "不分順序親代組合：$($pairKeys.Count) 組"
Write-Output "性別限定：$genderDirectedCount 列"
Write-Output "資料庫 SHA-256：$databaseHash"
Write-Output "配種表 SHA-256：$breedingHash"
