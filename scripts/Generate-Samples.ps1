[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $OutputDirectory,
    [Parameter(Mandatory = $true)][string] $SourceBundleDirectory,
    [Parameter(Mandatory = $true)][string] $CliAssemblyPath,
    [switch] $InitializeCandidateMetadata
)

. (Join-Path $PSScriptRoot 'SampleData.ps1')
$repoRoot = Split-Path $PSScriptRoot -Parent
$metadataPath = Join-Path $repoRoot 'release-candidate.json'
$checksumPath = Join-Path $repoRoot 'checksums.txt'
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
$definitions = @(Get-SampleDefinitions)
if (!(Test-Path -LiteralPath $CliAssemblyPath -PathType Leaf)) { throw 'Provide a compatible built NEMSweep CLI assembly for original-input validation.' }
$originals = Get-AdvancedInputEntries $SourceBundleDirectory
$sourceInputs = @($originals.Keys | ForEach-Object {
    [ordered]@{ name = $_; length = $originals[$_].LongLength; sha256 = (Get-SampleSha256 $originals[$_]) }
})
if ($InitializeCandidateMetadata) {
    if ((Test-Path $metadataPath) -or (Test-Path $checksumPath)) {
        throw 'Candidate metadata already exists. Initialization cannot overwrite pins.'
    }
} else {
    if (!(Test-Path $metadataPath)) { throw 'Missing release-candidate.json.' }
    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    if ($metadata.tag -cne 'v2026.10.1' -or $metadata.assets.Count -ne 2) { throw 'Unexpected candidate metadata.' }
    if (($sourceInputs | ConvertTo-Json -Depth 10 -Compress) -cne ($metadata.advancedInputs | ConvertTo-Json -Depth 10 -Compress)) {
        throw 'Original demand/EPW inputs differ from the reviewed source inventory.'
    }
}
foreach ($definition in $definitions) {
    if (Test-Path (Join-Path $outputRoot $definition.Asset)) {
        throw "Refusing to overwrite existing candidate: $($definition.Asset). Generate into a new directory."
    }
}
[IO.Directory]::CreateDirectory($outputRoot) | Out-Null
$assets = @()
foreach ($definition in $definitions) {
    [byte[]]$bytes = New-SampleArchiveBytes $definition $originals
    if ($definition.Asset -eq 'advanced-v2.zip') {
        Assert-AdvancedInputsWithCli $bytes $CliAssemblyPath
    }
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
        provenance = 'Simple demand/weather is synthetic. Advanced preserves original AEMO ACTUAL_OPERATIONAL_DEMAND_HH ZIPs for Australian NEM FY2026 (1 July 2025-30 June 2026), and original TMYx 2011-2025 EPW files, byte-for-byte. EPW typical-year profiles are not measured FY2026 weather. Third-party demand/weather redistribution rights and attribution require separate confirmation before publication.'
        advancedInputs = $sourceInputs
        assets = $assets
    }
    Write-SampleText $metadataPath ($metadata | ConvertTo-Json -Depth 10)
    Write-SampleText $checksumPath (($assets | ForEach-Object { "$($_.sha256)  $($_.name)" }) -join "`n")
}
