[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $VerificationDirectory,
    [Parameter(Mandatory = $true)][string] $CliAssemblyPath,
    [string] $SourceBundleDirectory,
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
    $recipeRoot = Join-Path $verificationRoot 'recipe'
    $recipeScripts = Join-Path $recipeRoot 'scripts'
    [IO.Directory]::CreateDirectory($recipeRoot) | Out-Null
    Copy-Item -LiteralPath $PSScriptRoot -Destination $recipeScripts -Recurse
    Copy-Item -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'LICENSE.md') -Destination $recipeRoot
    . (Join-Path $recipeScripts 'SampleData.ps1')
    $reviewedMetadata = Get-Content -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'release-candidate.json') -Raw | ConvertFrom-Json
    [string[]]$reviewedNames = @($reviewedMetadata.advancedInputs | ForEach-Object { $_.name })
    Assert-ReviewedAdvancedInputNames $reviewedNames
    foreach ($extension in @('.zip', '.epw')) {
        $removed = @($reviewedNames | Where-Object { $_.EndsWith($extension, [StringComparison]::Ordinal) })[0]
        Assert-Rejected { Assert-ReviewedAdvancedInputNames @($reviewedNames | Where-Object { $_ -cne $removed }) } 'reviewed demand/weather paths'
        Assert-Rejected { Assert-ReviewedAdvancedInputNames (@($reviewedNames | Where-Object { $_ -cne $removed }) + "$removed.unreviewed$extension") } 'reviewed demand/weather paths'
    }
    Assert-Rejected { Assert-ReviewedAdvancedInputNames ($reviewedNames + 'weather/NSW1/extra.epw') } 'reviewed demand/weather paths'
    if (!$SourceBundleDirectory) {
        Write-Host 'Hermetic tests use explicitly synthetic source fixtures, not the real release data.'
        $SourceBundleDirectory = Join-Path $verificationRoot 'synthetic-fixture'
        $advanced = @(Get-SampleDefinitions)[1]
        $fixture = [pscustomobject]@{
            Asset = 'simple-v2.zip'; Start = $advanced.Start; End = $advanced.End
            Regions = @($advanced.Regions | ForEach-Object {
                [pscustomobject]@{ Id = $_.Id; Directory = $_.Directory; Latitude = '-30'; Longitude = '150'; Temperature = 25; Wind = 5 }
            })
        }
        [IO.Directory]::CreateDirectory((Join-Path $SourceBundleDirectory 'demand\operational-demand-hh')) | Out-Null
        $manifest = [ordered]@{
            schemaVersion = 2; bundleId = 'synthetic-fixture'; name = 'Explicitly synthetic test fixture, not public Advanced data'
            period = @{ start = $advanced.Start; end = $advanced.End }
            regions = @($advanced.Regions | ForEach-Object { @{ regionId = $_.Id; weatherDirectory = $_.Directory } })
        }
        Write-SampleText (Join-Path $SourceBundleDirectory 'manifest.json') ($manifest | ConvertTo-Json -Depth 10)
        [IO.File]::WriteAllBytes((Join-Path $SourceBundleDirectory 'demand\operational-demand-hh\PUBLIC_ARCHIVE#SYNTHETIC#fixture.zip'),
            (New-SampleZipBytes @{ 'fixture.csv' = (New-SampleDemandBytes $fixture) }))
        for ($index = 0; $index -lt $fixture.Regions.Count; $index++) {
            $region = $fixture.Regions[$index]
            $roles = if ($region.Id -in @('NSW1', 'QLD1')) { @('solar', 'wind') } else { @('') }
            foreach ($role in $roles) {
                $directory = Join-Path (Join-Path $SourceBundleDirectory "weather\$($region.Directory)") $role
                [IO.Directory]::CreateDirectory($directory) | Out-Null
                [IO.File]::WriteAllBytes((Join-Path $directory 'synthetic-fixture.epw'), (New-SampleWeatherBytes $fixture $region $index))
            }
        }
        Assert-Rejected {
            & (Join-Path $recipeScripts 'Generate-Samples.ps1') -OutputDirectory (Join-Path $verificationRoot 'rejected-fixture') -SourceBundleDirectory $SourceBundleDirectory -CliAssemblyPath $CliAssemblyPath -InitializeCandidateMetadata
        } 'reviewed demand/weather paths'
        if ((Test-Path (Join-Path $recipeRoot 'release-candidate.json')) -or (Test-Path (Join-Path $recipeRoot 'checksums.txt')) -or (Test-Path (Join-Path $verificationRoot 'rejected-fixture'))) {
            throw 'Rejected synthetic bootstrap must not create metadata, checksums or candidate output.'
        }
        # Only the isolated test recipe substitutes an explicit fixture allowlist.
        $fixtureNames = @('demand/operational-demand-hh/PUBLIC_ARCHIVE#SYNTHETIC#fixture.zip')
        foreach ($region in $fixture.Regions) {
            $roles = if ($region.Id -in @('NSW1', 'QLD1')) { @('solar/', 'wind/') } else { @('') }
            foreach ($role in $roles) { $fixtureNames += "weather/$($region.Directory)/${role}synthetic-fixture.epw" }
        }
        $fixtureOverride = "function Get-ReviewedAdvancedInputNames {`n" + (($fixtureNames | ForEach-Object { "    '$_'" }) -join "`n") + "`n}"
        $copiedHelper = Join-Path $recipeScripts 'SampleData.ps1'
        Write-SampleText $copiedHelper ([IO.File]::ReadAllText($copiedHelper, $script:Utf8) + "`n" + $fixtureOverride)
        . $copiedHelper
    }
    $PSDefaultParameterValues = @{
        'Generate-Samples.ps1:SourceBundleDirectory' = $SourceBundleDirectory
        'Generate-Samples.ps1:CliAssemblyPath' = $CliAssemblyPath
        'Validate-Samples.ps1:CliAssemblyPath' = $CliAssemblyPath
        'Publish-Samples.ps1:CliAssemblyPath' = $CliAssemblyPath
        'Publish-Samples.ps1:ConfirmSourceRedistributionRights' = $true
    }
    $candidateRoot = Join-Path $verificationRoot 'candidates'
    & (Join-Path $recipeScripts 'Generate-Samples.ps1') -OutputDirectory $candidateRoot -InitializeCandidateMetadata
    $verificationRoot = $candidateRoot
    . (Join-Path $recipeScripts 'Validate-Samples.ps1') -CandidateDirectory $verificationRoot
    $advancedMemory = [IO.MemoryStream]::new([IO.File]::ReadAllBytes((Join-Path $verificationRoot 'advanced-v2.zip')), $false)
    $advancedArchive = [IO.Compression.ZipArchive]::new($advancedMemory, [IO.Compression.ZipArchiveMode]::Read)
    try {
        $advancedManifest = (Read-SampleText (Read-EntryBytes ($advancedArchive.GetEntry('manifest.json')))) | ConvertFrom-Json
        Assert-Condition ($advancedManifest.name -ceq 'Australian NEM FY2026 (1 July 2025-30 June 2026): AEMO operational demand and original TMYx 2011-2025 EPW weather') 'Advanced manifest must distinguish real FY2026 demand from original EPW typical-year weather.'
        foreach ($source in $metadata.advancedInputs) {
            $original = [IO.File]::ReadAllBytes((Join-Path $SourceBundleDirectory $source.name.Replace('/', '\')))
            Assert-Condition ((Get-SampleSha256 (Read-EntryBytes ($advancedArchive.GetEntry($source.name)))) -ceq (Get-SampleSha256 $original)) 'Every original demand/EPW file must be preserved byte-for-byte.'
        }
        $advancedEntries = [ordered]@{}
        foreach ($entry in $advancedArchive.Entries) { $advancedEntries[$entry.FullName] = Read-EntryBytes $entry }
        $weatherEntry = @($metadata.advancedInputs | Where-Object { $_.name.EndsWith('.epw', [StringComparison]::Ordinal) })[0].name
        $alteredWeather = [byte[]]$advancedEntries[$weatherEntry].Clone()
        $alteredWeather[0] = $alteredWeather[0] -bxor 1
        $advancedEntries[$weatherEntry] = $alteredWeather
        Assert-Rejected { Assert-SampleArchive (New-SampleZipBytes $advancedEntries) (@(Get-SampleDefinitions)[1]) } 'Original demand/EPW bytes differ from the reviewed source inventory'
    }
    finally { $advancedArchive.Dispose(); $advancedMemory.Dispose() }
    $reproduced = Join-Path $verificationRoot 'reproduced'
    & (Join-Path $recipeScripts 'Generate-Samples.ps1') -OutputDirectory $reproduced
    Assert-Rejected { & (Join-Path $recipeScripts 'Generate-Samples.ps1') -OutputDirectory $verificationRoot } 'Refusing to overwrite'
    Assert-Rejected { & (Join-Path $recipeScripts 'Generate-Samples.ps1') -OutputDirectory $verificationRoot -InitializeCandidateMetadata } 'cannot overwrite pins'
    Assert-Rejected { & (Join-Path $recipeScripts 'Validate-Samples.ps1') -CandidateDirectory (Join-Path $verificationRoot 'missing') } 'Missing candidate'
    Assert-Rejected { Get-AdvancedInputEntries '' } 'generated data is not a substitute'
    Assert-Rejected { Get-SampleDemandMw (@(Get-SampleDefinitions)[1]) $null ([DateTimeOffset]::Now) } 'Only Simple demand may be generated'

    $simple = @(Get-SampleDefinitions)[0]
    [byte[]]$simpleBytes = [IO.File]::ReadAllBytes((Join-Path $verificationRoot $simple.Asset))
    $simplePin = $metadata.assets | Where-Object { $_.name -ceq $simple.Asset }
    $reviewedMetadata = Get-Content -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'release-candidate.json') -Raw | ConvertFrom-Json
    Assert-SamplePin ($reviewedMetadata.assets | Where-Object { $_.name -ceq $simple.Asset }) $simpleBytes
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
    $global:MockExpectedWeatherDownloads = @($reviewedMetadata.advancedInputs |
        Where-Object { $_.name.EndsWith('.epw', [StringComparison]::Ordinal) } |
        ForEach-Object { [IO.Path]::GetFileName($_.name).Replace('.epw', '.zip') })
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
            $notesIndex = [Array]::IndexOf($args, '--notes')
            if ($notesIndex -lt 0) { throw 'Release notes must include the third-party licence notice.' }
            $notes = $args[$notesIndex + 1]
            if (!$notes.Contains('Lawrie, Linda K, Drury B Crawley. 2026.') -or
                !$notes.Contains('All seven EPW files remain included in the Advanced ZIP, unaltered.') -or
                !$notes.Contains('https://climate.onebuilding.org/WMO_Region_5_Southwest_Pacific/AUS_Australia/')) {
                throw 'Release notes must preserve the EPW citation, unaltered-data notice and upstream links.'
            }
            if ($global:MockExpectedWeatherDownloads.Count -ne 7) { throw 'Expected seven original EPW downloads.' }
            foreach ($download in $global:MockExpectedWeatherDownloads) {
                if (!$notes.Contains($download)) { throw "Release notes omit the original EPW download: $download" }
            }
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
    $publishScript = Join-Path $recipeScripts 'Publish-Samples.ps1'
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
    Assert-Rejected { & $publishScript -CandidateDirectory $verificationRoot -ReviewedMainCommit $global:MockCommit -PublishReviewedCandidates -ConfirmSourceRedistributionRights:$false } 'Confirm redistribution rights and attribution for both'
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
    Write-Host 'PASS: deterministic regeneration, unchanged Simple pin, original-source preservation, CLI coverage, mutation checks and mocked publication gates.'
}
finally {
    Remove-Item Function:\git, Function:\gh -ErrorAction SilentlyContinue
    $cleanupRoot = [IO.Path]::GetFullPath($VerificationDirectory)
    if (!$KeepVerificationDirectory -and (Test-Path -LiteralPath $cleanupRoot)) {
        Remove-Item -LiteralPath $cleanupRoot -Recurse -Force
    }
}
