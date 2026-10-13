[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $OutputDirectory,
    [switch] $InitializeCandidateMetadata
)

. (Join-Path $PSScriptRoot 'SampleData.ps1')
$repoRoot = Split-Path $PSScriptRoot -Parent
$metadataPath = Join-Path $repoRoot 'release-candidate.json'
$checksumPath = Join-Path $repoRoot 'checksums.txt'
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
$definitions = @(Get-SampleDefinitions)
if ($InitializeCandidateMetadata) {
    if ((Test-Path $metadataPath) -or (Test-Path $checksumPath)) {
        throw 'Candidate metadata already exists. Initialization cannot overwrite pins.'
    }
} else {
    if (!(Test-Path $metadataPath)) { throw 'Missing release-candidate.json.' }
    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    if ($metadata.tag -cne 'v2026.10.1' -or $metadata.assets.Count -ne 2) { throw 'Unexpected candidate metadata.' }
}
foreach ($definition in $definitions) {
    if (Test-Path (Join-Path $outputRoot $definition.Asset)) {
        throw "Refusing to overwrite existing candidate: $($definition.Asset). Generate into a new directory."
    }
}
[IO.Directory]::CreateDirectory($outputRoot) | Out-Null
$assets = @()
foreach ($definition in $definitions) {
    [byte[]]$bytes = New-SampleArchiveBytes $definition
    $asset = [ordered]@{ name = $definition.Asset; length = $bytes.LongLength; sha256 = (Get-SampleSha256 $bytes) }
    if (!$InitializeCandidateMetadata) {
        $pins = @($metadata.assets | Where-Object { $_.name -ceq $definition.Asset })
        if ($pins.Count -ne 1) { throw "Missing or duplicate pin: $($definition.Asset)." }
        Assert-SamplePin $pins[0] $bytes
    }
    [IO.File]::WriteAllBytes((Join-Path $outputRoot $definition.Asset), $bytes)
    $assets += $asset
    Write-Host "$($asset.name): $($asset.length) bytes, SHA256 $($asset.sha256)"
}
if ($InitializeCandidateMetadata) {
    $metadata = [ordered]@{
        repository = 'HasinthaAttanayake/NEMSweep.Samples'
        tag = 'v2026.10.1'
        status = 'local-candidate-not-published'
        toolchain = 'Windows PowerShell 5.1.26100.9444 / .NET Framework 4.8.1 (4.8.09221); System.IO.Compression; NoCompression'
        provenance = 'Entirely synthetic; Simple adapted from NEMSweep 766316fbe1ce8bc965d2ed38e5500aa1f8c761e0 examples/custom-grid/Generate-SyntheticGrid.ps1. No observed source data.'
        assets = $assets
    }
    Write-SampleText $metadataPath ($metadata | ConvertTo-Json -Depth 10)
    Write-SampleText $checksumPath (($assets | ForEach-Object { "$($_.sha256)  $($_.name)" }) -join "`n")
}
