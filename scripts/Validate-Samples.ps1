[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $CandidateDirectory,
    [Parameter(Mandatory = $true)][string] $CliAssemblyPath
)

. (Join-Path $PSScriptRoot 'SampleData.ps1')

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw $Message }
}

function Read-EntryBytes($Entry) {
    $inputStream = $Entry.Open()
    $memory = [IO.MemoryStream]::new()
    try { $inputStream.CopyTo($memory); return ,$memory.ToArray() }
    finally { $inputStream.Dispose(); $memory.Dispose() }
}

function Read-SampleText([byte[]] $Bytes) {
    $text = $script:Utf8.GetString($Bytes)
    Assert-Condition (!$text.StartsWith([string][char]0xfeff, [StringComparison]::Ordinal) -and !$text.Contains("`r") -and $text.EndsWith("`n", [StringComparison]::Ordinal)) 'Text must be UTF-8 without BOM, with LF lines and a final newline.'
    return $text
}

function Assert-ZipEntries($Archive, [string[]] $Names) {
    [Array]::Sort($Names, [StringComparer]::Ordinal)
    Assert-Condition ($Archive.Entries.Count -eq $Names.Count) 'Unexpected ZIP entry count; only allowlisted raw inputs may be packaged.'
    for ($i = 0; $i -lt $Names.Count; $i++) {
        $entry = $Archive.Entries[$i]
        Assert-Condition ($entry.FullName -ceq $Names[$i]) "Unexpected ZIP entry or order: $($entry.FullName)."
        Assert-Condition ($entry.LastWriteTime.DateTime -eq $script:ZipTimestamp.DateTime) 'Non-deterministic ZIP timestamp.'
        Assert-Condition ($entry.ExternalAttributes -eq 0) 'Unexpected ZIP external attributes.'
    }
}

function Assert-SampleArchive([byte[]] $Bytes, $Definition) {
    $memory = [IO.MemoryStream]::new($Bytes, $false)
    $archive = [IO.Compression.ZipArchive]::new($memory, [IO.Compression.ZipArchiveMode]::Read)
    try {
        $advanced = $Definition.Asset -eq 'advanced-v2.zip'
        $names = @('manifest.json')
        if ($advanced) {
            $names += @($metadata.advancedInputs | ForEach-Object { $_.name })
        } else {
            $names += 'demand/operational-demand-hh/synthetic-demand.zip'
            $names += @($Definition.Regions | ForEach-Object { "weather/$($_.Directory)/synthetic-typical-year.epw" })
        }
        Assert-ZipEntries $archive $names
        $manifest = (Read-SampleText (Read-EntryBytes ($archive.GetEntry('manifest.json')))) | ConvertFrom-Json
        Assert-Condition ($manifest.PSObject.Properties.Name.Count -eq 6) 'Unexpected manifest properties.'
        Assert-Condition ($manifest.'$schema' -ceq 'https://raw.githubusercontent.com/HasinthaAttanayake/NEMSweep/main/schema/manifest-v2.json') 'Unexpected manifest schema hint.'
        Assert-Condition ($manifest.schemaVersion -eq 2 -and $manifest.bundleId -ceq 'bundle' -and $manifest.name -ceq $Definition.Name) 'Unexpected manifest identity.'
        Assert-Condition ($manifest.period.PSObject.Properties.Name.Count -eq 2 -and $manifest.period.start -ceq $Definition.Start -and $manifest.period.end -ceq $Definition.End) 'Incorrect full period or fixed UTC+10 offset.'
        Assert-Condition ($manifest.regions.Count -eq $Definition.Regions.Count) 'Incorrect region count.'
        for ($i = 0; $i -lt $Definition.Regions.Count; $i++) {
            Assert-Condition ($manifest.regions[$i].PSObject.Properties.Name.Count -eq 2 -and
                $manifest.regions[$i].regionId -ceq $Definition.Regions[$i].Id -and
                $manifest.regions[$i].weatherDirectory -ceq $Definition.Regions[$i].Directory) 'Incorrect region/weather mapping.'
        }

        if ($advanced) {
            foreach ($source in $metadata.advancedInputs) {
                [byte[]]$sourceBytes = Read-EntryBytes ($archive.GetEntry($source.name))
                Assert-Condition ($sourceBytes.LongLength -eq $source.length -and (Get-SampleSha256 $sourceBytes) -ceq $source.sha256) 'Original demand/EPW bytes differ from the reviewed source inventory.'
            }
            Assert-AdvancedInputsWithCli $Bytes $CliAssemblyPath
            Write-Host "Validated $($Definition.Asset): original demand/EPW source bytes and complete FY2026 input coverage."
            return
        }
        $demandMemory = [IO.MemoryStream]::new((Read-EntryBytes ($archive.GetEntry('demand/operational-demand-hh/synthetic-demand.zip'))), $false)
        $demandZip = [IO.Compression.ZipArchive]::new($demandMemory, [IO.Compression.ZipArchiveMode]::Read)
        try {
            Assert-ZipEntries $demandZip @('operational-demand.csv')
            $csv = (Read-SampleText (Read-EntryBytes $demandZip.Entries[0])).TrimEnd("`n").Split("`n")
        }
        finally { $demandZip.Dispose(); $demandMemory.Dispose() }
        Assert-Condition ($csv[0] -ceq 'C,NEMP.WORLD,ACTUAL_OPERATIONAL_DEMAND_HH,SYNTHETIC,PUBLIC') 'Missing synthetic demand provenance.'
        Assert-Condition ($csv[1] -ceq 'I,OPERATIONAL_DEMAND,ACTUAL,3,INTERVAL_DATETIME,REGIONID,OPERATIONAL_DEMAND') 'Incorrect demand schema.'
        $start = [DateTimeOffset]::Parse($Definition.Start, $script:Invariant)
        $end = [DateTimeOffset]::Parse($Definition.End, $script:Invariant)
        $intervals = [int](($end - $start).TotalMinutes / 30)
        Assert-Condition ($intervals -eq 17520 -and $csv.Count -eq (2 + $intervals * $Definition.Regions.Count)) 'Incomplete half-hour demand coverage.'
        $line = 2
        for ($interval = 0; $interval -lt $intervals; $interval++) {
            $date = $start.AddMinutes($interval * 30)
            $timestamp = $date.AddMinutes(30).ToString('yyyy/MM/dd HH:mm:ss', $script:Invariant)
            foreach ($region in $Definition.Regions) {
                $mw = (Get-SampleDemandMw $Definition $region $date).ToString($script:Invariant)
                Assert-Condition ($csv[$line] -ceq "D,OPERATIONAL_DEMAND,ACTUAL,3,$timestamp,$($region.Id),$mw") "Incorrect interval-end demand at line $line."
                $line++
            }
        }

        for ($index = 0; $index -lt $Definition.Regions.Count; $index++) {
            $region = $Definition.Regions[$index]
            $epw = (Read-SampleText (Read-EntryBytes ($archive.GetEntry("weather/$($region.Directory)/synthetic-typical-year.epw")))).TrimEnd("`n").Split("`n")
            Assert-Condition ($epw.Count -eq 8768) 'Incomplete hourly EPW coverage.'
            $location = $epw[0].Split(',')
            Assert-Condition ($location.Count -eq 10 -and $location[0] -ceq 'LOCATION' -and $location[1] -ceq "Synthetic $($region.Id)" -and
                $location[4] -ceq 'Synthetic' -and $location[5] -ceq ($index + 1).ToString('D6', $script:Invariant) -and
                $location[6] -ceq $region.Latitude -and $location[7] -ceq $region.Longitude -and $location[8] -ceq '10') 'Incorrect synthetic weather location or input offset.'
            Assert-Condition ($epw[1] -ceq 'DESIGN CONDITIONS,0' -and $epw[2] -ceq 'TYPICAL/EXTREME PERIODS,0' -and
                $epw[3] -ceq 'GROUND TEMPERATURES,0' -and $epw[4] -ceq 'HOLIDAYS/DAYLIGHT SAVING,No' -and
                $epw[5] -ceq 'COMMENTS 1,Generated synthetic weather; not a measured site' -and
                $epw[6] -ceq 'COMMENTS 2,NEMSweep.Samples v2026.10.1; illustrative typical year 2001' -and
                $epw[7] -ceq 'DATA PERIODS,1,1,Data,Monday,1/1,12/31') 'Incorrect EPW headers or provenance.'
            for ($hour = 0; $hour -lt 8760; $hour++) {
                $date = [DateTime]::new(2001, 1, 1).AddHours($hour)
                $fields = $epw[$hour + 8].Split(',')
                Assert-Condition ($fields.Count -eq 22 -and $fields[0] -ceq '2001' -and
                    [int]$fields[1] -eq $date.Month -and [int]$fields[2] -eq $date.Day -and [int]$fields[3] -eq ($date.Hour + 1) -and
                    $fields[5] -ceq 'A0' -and [int]$fields[6] -eq $region.Temperature -and [int]$fields[21] -eq $region.Wind) "Incorrect EPW date/value at hour $hour."
                $daylight = $date.Hour -ge 6 -and $date.Hour -lt 18
                $ghi = if ($daylight) { '500' } else { '0' }
                $dni = if ($daylight) { '600' } else { '0' }
                $dhi = if ($daylight) { '100' } else { '0' }
                Assert-Condition ($fields[13] -ceq $ghi -and $fields[14] -ceq $dni -and $fields[15] -ceq $dhi) "Incorrect EPW radiation at hour $hour."
            }
        }
        Write-Host "$($Definition.Asset): $($Definition.Regions.Count) regions; $intervals half-hours/region; 8760 weather hours/region; root layout and UTC+10 validated."
    }
    finally { $archive.Dispose(); $memory.Dispose() }
}

$repoRoot = Split-Path $PSScriptRoot -Parent
$metadata = Get-Content -LiteralPath (Join-Path $repoRoot 'release-candidate.json') -Raw | ConvertFrom-Json
Assert-Condition ($metadata.repository -ceq 'HasinthaAttanayake/NEMSweep.Samples' -and $metadata.tag -ceq 'v2026.10.1' -and $metadata.assets.Count -eq 2) 'Incorrect candidate repository, tag or asset count.'
Assert-ReviewedAdvancedInputNames @($metadata.advancedInputs | ForEach-Object { $_.name })
$expectedChecksums = (($metadata.assets | ForEach-Object { "$($_.sha256)  $($_.name)" }) -join "`n") + "`n"
Assert-Condition ([IO.File]::ReadAllText((Join-Path $repoRoot 'checksums.txt'), $script:Utf8) -ceq $expectedChecksums) 'checksums.txt differs from release-candidate.json.'
foreach ($definition in (Get-SampleDefinitions)) {
    $pins = @($metadata.assets | Where-Object { $_.name -ceq $definition.Asset })
    Assert-Condition ($pins.Count -eq 1) "Missing or duplicate candidate pin: $($definition.Asset)."
    $path = Join-Path ([IO.Path]::GetFullPath($CandidateDirectory)) $definition.Asset
    Assert-Condition (Test-Path -LiteralPath $path -PathType Leaf) "Missing candidate: $path."
    [byte[]]$bytes = [IO.File]::ReadAllBytes($path)
    Assert-SamplePin $pins[0] $bytes
    Assert-SampleArchive $bytes $definition
}
