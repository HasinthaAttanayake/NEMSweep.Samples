[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $VerificationDirectory,
    [switch] $KeepVerificationDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$verificationRoot = [IO.Path]::GetFullPath($VerificationDirectory)
if (Test-Path -LiteralPath $verificationRoot) { throw 'Choose a new verification directory; tests never overwrite existing files.' }

function Assert-Rejected([scriptblock] $Action, [string] $ExpectedMessage) {
    try { & $Action }
    catch {
        if ($_.Exception.Message -notlike "*$ExpectedMessage*") { throw }
        Write-Host "Expected rejection: $ExpectedMessage"
        return
    }
    throw "Expected rejection did not occur: $ExpectedMessage"
}

try {
    & (Join-Path $PSScriptRoot 'Generate-Samples.ps1') -OutputDirectory $verificationRoot
    . (Join-Path $PSScriptRoot 'Validate-Samples.ps1') -CandidateDirectory $verificationRoot
    Assert-Rejected { & (Join-Path $PSScriptRoot 'Generate-Samples.ps1') -OutputDirectory $verificationRoot } 'Refusing to overwrite'
    Assert-Rejected { & (Join-Path $PSScriptRoot 'Generate-Samples.ps1') -OutputDirectory $verificationRoot -InitializeCandidateMetadata } 'cannot overwrite pins'
    Assert-Rejected { & (Join-Path $PSScriptRoot 'Validate-Samples.ps1') -CandidateDirectory (Join-Path $verificationRoot 'missing') } 'Missing candidate'

    $simple = @(Get-SampleDefinitions)[0]
    [byte[]]$simpleBytes = [IO.File]::ReadAllBytes((Join-Path $verificationRoot $simple.Asset))
    $simplePin = $metadata.assets | Where-Object { $_.name -ceq $simple.Asset }
    $corrupt = [byte[]]$simpleBytes.Clone()
    $corrupt[0] = $corrupt[0] -bxor 1
    Assert-Rejected { Assert-SamplePin $simplePin $corrupt } 'differs from its checked-in length/SHA256'
    Assert-Rejected { Read-SampleText ($script:Utf8.GetBytes("bad`r`n")) } 'UTF-8 without BOM'
    Assert-Rejected { Read-SampleText ([byte[]]@(239, 187, 191, 10)) } 'UTF-8 without BOM'

    $memory = [IO.MemoryStream]::new($simpleBytes, $false)
    $archive = [IO.Compression.ZipArchive]::new($memory, [IO.Compression.ZipArchiveMode]::Read)
    $entries = [ordered]@{}
    try {
        foreach ($entry in $archive.Entries) { $entries[$entry.FullName] = Read-EntryBytes $entry }
    }
    finally { $archive.Dispose(); $memory.Dispose() }
    $entries['run.ps1'] = $script:Utf8.GetBytes("Write-Host unsafe`n")
    Assert-Rejected { Assert-SampleArchive (New-SampleZipBytes $entries) $simple } 'only allowlisted raw inputs'
    $entries.Remove('run.ps1')
    $originalManifest = $entries['manifest.json']
    $entries['manifest.json'] = $script:Utf8.GetBytes($script:Utf8.GetString($originalManifest).Replace('station-01', 'wrong-station'))
    Assert-Rejected { Assert-SampleArchive (New-SampleZipBytes $entries) $simple } 'Incorrect region/weather mapping'
    $entries['manifest.json'] = $originalManifest
    $weatherName = 'weather/station-01/synthetic-typical-year.epw'
    $originalWeather = $entries[$weatherName]
    $entries[$weatherName] = $script:Utf8.GetBytes($script:Utf8.GetString($originalWeather).Replace(',150.0,10,0', ',150.0,11,0'))
    Assert-Rejected { Assert-SampleArchive (New-SampleZipBytes $entries) $simple } 'input offset'
    $entries[$weatherName] = $originalWeather
    $entries['demand/operational-demand-hh/synthetic-demand.zip'] = New-SampleZipBytes @{
        'operational-demand.csv' = $script:Utf8.GetBytes("C,NEMP.WORLD,ACTUAL_OPERATIONAL_DEMAND_HH,SYNTHETIC,PUBLIC`nI,OPERATIONAL_DEMAND,ACTUAL,3,INTERVAL_DATETIME,REGIONID,OPERATIONAL_DEMAND`n")
    }
    Assert-Rejected { Assert-SampleArchive (New-SampleZipBytes $entries) $simple } 'Incomplete half-hour demand coverage'

    # Publication tests shadow git/gh only within this test process; no network or release writes.
    $global:MockBranch = 'main'
    $global:MockCommit = '0000000000000000000000000000000000000000'
    $global:MockRemoteCommit = $global:MockCommit
    $global:MockDirty = $false
    $global:MockOrigin = 'https://github.com/HasinthaAttanayake/NEMSweep.Samples.git'
    $global:MockMerged = $true
    $global:MockReleaseExists = $false
    $global:MockTagMismatch = $false
    $global:MockPublished = $false
    function global:git {
        $global:LASTEXITCODE = 0
        switch ($args[2]) {
            'branch' { return $global:MockBranch }
            'status' { if ($global:MockDirty) { return ' M README.md' }; return }
            'rev-parse' { return $global:MockCommit }
            'remote' { return $global:MockOrigin }
            default { throw "Unexpected mocked git call: $args" }
        }
    }
    function global:gh {
        $global:LASTEXITCODE = 0
        if ($args[0] -eq 'release') {
            if ($args[1] -ne 'create' -or $args[2] -cne 'v2026.10.1' -or $args -contains '--clobber') { throw 'Unexpected release command.' }
            $global:MockPublished = $true
            return 'mock publication only; no network call'
        }
        $endpoint = $args[$args.Count - 1]
        if ($endpoint -like '*/commits/main') { return "{`"sha`":`"$global:MockRemoteCommit`"}" }
        if ($endpoint -like '*/pulls') {
            if (!$global:MockMerged) { return '[]' }
            return "[{`"merged_at`":`"2026-10-13`",`"base`":{`"ref`":`"main`",`"repo`":{`"full_name`":`"HasinthaAttanayake/NEMSweep.Samples`"}},`"merge_commit_sha`":`"$global:MockCommit`"}]"
        }
        if ($endpoint -like '*/matching-refs/*') {
            if ($global:MockTagMismatch) { return '[{"ref":"refs/tags/v2026.10.1","object":{"type":"commit","sha":"wrong"}}]' }
            return '[]'
        }
        if ($endpoint -like '*/releases?per_page=100') {
            if ($global:MockReleaseExists) { return '[[{"tag_name":"v2026.10.1"}]]' }
            return '[[]]'
        }
        throw "Unexpected mocked gh call: $args"
    }
    $publishScript = Join-Path $PSScriptRoot 'Publish-Samples.ps1'
    Assert-Rejected { & $publishScript -CandidateDirectory $verificationRoot -ReviewedMainCommit $global:MockCommit } 'Publication is disabled'
    $global:MockBranch = 'feat/synthetic-starters'
    Assert-Rejected { & $publishScript -CandidateDirectory $verificationRoot -ReviewedMainCommit $global:MockCommit -PublishReviewedCandidates } 'merged main branch'
    $global:MockBranch = 'main'
    $global:MockDirty = $true
    Assert-Rejected { & $publishScript -CandidateDirectory $verificationRoot -ReviewedMainCommit $global:MockCommit -PublishReviewedCandidates } 'clean working tree'
    $global:MockDirty = $false
    Assert-Rejected { & $publishScript -CandidateDirectory $verificationRoot -ReviewedMainCommit ('1' * 40) -PublishReviewedCandidates } 'HEAD differs'
    $global:MockOrigin = 'https://github.com/HasinthaAttanayake/NEMSweep.git'
    Assert-Rejected { & $publishScript -CandidateDirectory $verificationRoot -ReviewedMainCommit $global:MockCommit -PublishReviewedCandidates } 'Unexpected origin'
    $global:MockOrigin = 'https://github.com/HasinthaAttanayake/NEMSweep.Samples.git'
    $global:MockRemoteCommit = '1' * 40
    Assert-Rejected { & $publishScript -CandidateDirectory $verificationRoot -ReviewedMainCommit $global:MockCommit -PublishReviewedCandidates } 'current remote main tip'
    $global:MockRemoteCommit = $global:MockCommit
    $global:MockMerged = $false
    Assert-Rejected { & $publishScript -CandidateDirectory $verificationRoot -ReviewedMainCommit $global:MockCommit -PublishReviewedCandidates } 'merged samples pull request'
    $global:MockMerged = $true
    Assert-Rejected { & $publishScript -CandidateDirectory (Join-Path $verificationRoot 'missing') -ReviewedMainCommit $global:MockCommit -PublishReviewedCandidates } 'Missing candidate'
    [IO.File]::WriteAllBytes((Join-Path $verificationRoot $simple.Asset), $corrupt)
    Assert-Rejected { & $publishScript -CandidateDirectory $verificationRoot -ReviewedMainCommit $global:MockCommit -PublishReviewedCandidates } 'differs from its checked-in length/SHA256'
    [IO.File]::WriteAllBytes((Join-Path $verificationRoot $simple.Asset), $simpleBytes)
    $global:MockTagMismatch = $true
    Assert-Rejected { & $publishScript -CandidateDirectory $verificationRoot -ReviewedMainCommit $global:MockCommit -PublishReviewedCandidates } 'Existing tag'
    $global:MockTagMismatch = $false
    $global:MockReleaseExists = $true
    Assert-Rejected { & $publishScript -CandidateDirectory $verificationRoot -ReviewedMainCommit $global:MockCommit -PublishReviewedCandidates } 'Release already exists'
    $global:MockReleaseExists = $false
    & $publishScript -CandidateDirectory $verificationRoot -ReviewedMainCommit $global:MockCommit -PublishReviewedCandidates
    if (!$global:MockPublished) { throw 'Approved mocked publication was not reached.' }
    Write-Host 'PASS: exact pinned regeneration, structural coverage, mutation checks and mocked publication gates.'
}
finally {
    Remove-Item Function:\git, Function:\gh -ErrorAction SilentlyContinue
    if (!$KeepVerificationDirectory -and (Test-Path -LiteralPath $verificationRoot)) {
        Remove-Item -LiteralPath $verificationRoot -Recurse -Force
    }
}
