[CmdletBinding()]
param(
    [Alias('Parent1')][string]$親代1,
    [Alias('Parent2')][string]$親代2,
    [Alias('Child')][string]$子代,
    [Alias('Parent')][string]$單一親代,
    [Alias('First')][ValidateRange(0, 44851)][int]$前幾筆 = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$tablePath = Join-Path $PSScriptRoot '完整配種表.csv'
if (-not (Test-Path -LiteralPath $tablePath -PathType Leaf)) {
    throw "找不到完整配種表：$tablePath。請先執行「更新與驗證配種表.ps1」。"
}

function Test-PalName {
    param(
        [Parameter(Mandatory = $true)][object]$Row,
        [Parameter(Mandatory = $true)][ValidateSet('親代1', '親代2', '子代')][string]$Role,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $traditionalChineseName = $Row.PSObject.Properties["$($Role)繁中"].Value
    $englishName = $Row.PSObject.Properties["$($Role)英文"].Value
    $internalName = $Row.PSObject.Properties["$($Role)內部名稱"].Value

    return @($traditionalChineseName, $englishName, $internalName) -contains $Name
}

$hasParentPair = -not [string]::IsNullOrWhiteSpace($親代1) -and -not [string]::IsNullOrWhiteSpace($親代2)
$hasChild = -not [string]::IsNullOrWhiteSpace($子代)
$hasSingleParent = -not [string]::IsNullOrWhiteSpace($單一親代)
$modeCount = @($hasParentPair, $hasChild, $hasSingleParent | Where-Object { $_ }).Count

if ($modeCount -ne 1) {
    Write-Output '請一次使用一種查詢方式：'
    Write-Output '  .\查詢配種.ps1 -親代1 金棘獸 -親代2 霄龍'
    Write-Output '  .\查詢配種.ps1 -子代 泰鋒'
    Write-Output '  .\查詢配種.ps1 -單一親代 金棘獸'
    Write-Output '名稱可使用繁中、英文或 PalCalc 內部名稱；可加「-前幾筆 20」限制輸出。'
    exit 1
}

$rows = Import-Csv -LiteralPath $tablePath -Encoding UTF8

if ($hasParentPair) {
    Write-Verbose "雙親查詢：親代1=[$親代1]；親代2=[$親代2]"
    $results = @($rows | Where-Object {
        $matchesOriginalOrder =
            (Test-PalName $_ '親代1' $親代1) -and
            (Test-PalName $_ '親代2' $親代2)
        $matchesReversedOrder =
            (Test-PalName $_ '親代1' $親代2) -and
            (Test-PalName $_ '親代2' $親代1)

        $matchesOriginalOrder -or $matchesReversedOrder
    })
}
elseif ($hasChild) {
    $results = @($rows | Where-Object { Test-PalName $_ '子代' $子代 })
}
else {
    $results = @($rows | Where-Object {
        (Test-PalName $_ '親代1' $單一親代) -or (Test-PalName $_ '親代2' $單一親代)
    })
}

if ($results.Count -eq 0) {
    Write-Warning '查無結果。請先用「帕魯索引.csv」確認繁中、英文或內部名稱。'
    exit 2
}

Write-Host "找到 $($results.Count) 筆結果。"

if ($前幾筆 -gt 0) {
    $results = @($results | Select-Object -First $前幾筆)
}

$results | Select-Object `
    @{ Name = '親代1'; Expression = { $_.'親代1繁中' } },
    @{ Name = '性別1'; Expression = { $_.'親代1性別' } },
    @{ Name = '親代2'; Expression = { $_.'親代2繁中' } },
    @{ Name = '性別2'; Expression = { $_.'親代2性別' } },
    @{ Name = '子代'; Expression = { $_.'子代繁中' } },
    '性別限定'
