# Maintainer-only producer: verified on Windows PowerShell 5.1 / .NET Framework 4.8.1.
# PowerShell 7 on Linux/macOS is not a verified regeneration toolchain.
# Downloading the ZIPs or using CLI quick-start does not run these scripts.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$script:Invariant = [Globalization.CultureInfo]::InvariantCulture
$script:Utf8 = [Text.UTF8Encoding]::new($false, $true)
$script:ZipTimestamp = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)

function Write-SampleText([string] $Path, [string] $Text) {
    [IO.File]::WriteAllText($Path, $Text.Replace("`r`n", "`n").TrimEnd("`n") + "`n", $script:Utf8)
}

function Get-SampleDefinitions {
    @(
        [pscustomobject]@{
            Asset = 'simple-v2.zip'; Name = 'Synthetic Island-X calendar 2025 demonstration'
            Start = '2025-01-01T00:00:00+10:00'; End = '2026-01-01T00:00:00+10:00'
            Regions = @([pscustomobject]@{
                Id = 'Island-X'; Directory = 'station-01'; BaseMw = 45
                Latitude = '-20.0'; Longitude = '150.0'; Temperature = 25; Wind = 5
            })
        },
        [pscustomobject]@{
            Asset = 'advanced-v2.zip'; Name = 'Synthetic five-region FY2026 demonstration'
            Start = '2025-07-01T00:00:00+10:00'; End = '2026-07-01T00:00:00+10:00'
            Regions = @(
                [pscustomobject]@{ Id = 'NSW1'; Directory = 'nsw1'; BaseMw = 7500; Latitude = '-33.9'; Longitude = '151.2'; Temperature = 22; Wind = 5 },
                [pscustomobject]@{ Id = 'QLD1'; Directory = 'qld1'; BaseMw = 6000; Latitude = '-27.5'; Longitude = '153.0'; Temperature = 26; Wind = 4 },
                [pscustomobject]@{ Id = 'SA1'; Directory = 'sa1'; BaseMw = 1500; Latitude = '-34.9'; Longitude = '138.6'; Temperature = 23; Wind = 6 },
                [pscustomobject]@{ Id = 'TAS1'; Directory = 'tas1'; BaseMw = 1000; Latitude = '-42.9'; Longitude = '147.3'; Temperature = 15; Wind = 7 },
                [pscustomobject]@{ Id = 'VIC1'; Directory = 'vic1'; BaseMw = 4500; Latitude = '-37.8'; Longitude = '145.0'; Temperature = 20; Wind = 5 }
            )
        }
    )
}

function Get-SampleDemandMw($Definition, $Region, [DateTimeOffset] $IntervalStart) {
    if ($Definition.Asset -eq 'simple-v2.zip') {
        if ($IntervalStart.Hour -ge 8 -and $IntervalStart.Hour -lt 20) { return 60 }
        return 30
    }
    $dailyPercent = if ($IntervalStart.Hour -ge 8 -and $IntervalStart.Hour -lt 20) { 115 } else { 85 }
    $seasonalPercent = if ($IntervalStart.Month -in @(12, 1, 2, 6, 7, 8)) { 110 } else { 95 }
    $weeklyPercent = if ($IntervalStart.DayOfWeek -in @([DayOfWeek]::Saturday, [DayOfWeek]::Sunday)) { 92 } else { 100 }
    return [int][Math]::Round($Region.BaseMw * $dailyPercent * $seasonalPercent * $weeklyPercent / 1000000.0, 0, [MidpointRounding]::AwayFromZero)
}

function New-SampleDemandBytes($Definition) {
    $text = [Text.StringBuilder]::new()
    [void]$text.Append("C,NEMP.WORLD,ACTUAL_OPERATIONAL_DEMAND_HH,SYNTHETIC,PUBLIC`n")
    [void]$text.Append("I,OPERATIONAL_DEMAND,ACTUAL,3,INTERVAL_DATETIME,REGIONID,OPERATIONAL_DEMAND`n")
    $start = [DateTimeOffset]::Parse($Definition.Start, $script:Invariant)
    $end = [DateTimeOffset]::Parse($Definition.End, $script:Invariant)
    for ($date = $start; $date -lt $end; $date = $date.AddMinutes(30)) {
        $timestamp = $date.AddMinutes(30).ToString('yyyy/MM/dd HH:mm:ss', $script:Invariant)
        foreach ($region in $Definition.Regions) {
            $mw = (Get-SampleDemandMw $Definition $region $date).ToString($script:Invariant)
            [void]$text.Append("D,OPERATIONAL_DEMAND,ACTUAL,3,$timestamp,$($region.Id),$mw`n")
        }
    }
    return ,$script:Utf8.GetBytes($text.ToString())
}

function New-SampleWeatherBytes($Definition, $Region, [int] $Index) {
    $text = [Text.StringBuilder]::new()
    $station = ($Index + 1).ToString('D6', $script:Invariant)
    [void]$text.Append("LOCATION,Synthetic $($Region.Id),NA,XX,Synthetic,$station,$($Region.Latitude),$($Region.Longitude),10,0`n")
    [void]$text.Append("DESIGN CONDITIONS,0`nTYPICAL/EXTREME PERIODS,0`nGROUND TEMPERATURES,0`n")
    [void]$text.Append("HOLIDAYS/DAYLIGHT SAVING,No`nCOMMENTS 1,Generated synthetic weather; not a measured site`n")
    [void]$text.Append("COMMENTS 2,NEMSweep.Samples v2026.10.1; illustrative typical year 2001`n")
    [void]$text.Append("DATA PERIODS,1,1,Data,Monday,1/1,12/31`n")
    for ($hour = 0; $hour -lt 8760; $hour++) {
        $date = [DateTime]::new(2001, 1, 1).AddHours($hour)
        [string[]]$fields = @('2001', $date.Month.ToString($script:Invariant), $date.Day.ToString($script:Invariant),
            ($date.Hour + 1).ToString($script:Invariant), '0', 'A0', $Region.Temperature.ToString($script:Invariant),
            '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', $Region.Wind.ToString($script:Invariant))
        if ($date.Hour -ge 6 -and $date.Hour -lt 18) {
            $fields[13] = '500'; $fields[14] = '600'; $fields[15] = '100'
        }
        [void]$text.Append([string]::Join(',', $fields)).Append("`n")
    }
    return ,$script:Utf8.GetBytes($text.ToString())
}

function New-SampleZipBytes([Collections.IDictionary] $Entries) {
    $memory = [IO.MemoryStream]::new()
    $archive = [IO.Compression.ZipArchive]::new($memory, [IO.Compression.ZipArchiveMode]::Create, $true)
    try {
        [string[]]$names = @($Entries.Keys)
        [Array]::Sort($names, [StringComparer]::Ordinal)
        foreach ($name in $names) {
            $entry = $archive.CreateEntry($name, [IO.Compression.CompressionLevel]::NoCompression)
            $entry.LastWriteTime = $script:ZipTimestamp
            $entry.ExternalAttributes = 0
            $stream = $entry.Open()
            try { $stream.Write($Entries[$name], 0, $Entries[$name].Length) }
            finally { $stream.Dispose() }
        }
    }
    finally { $archive.Dispose() }
    try { return ,$memory.ToArray() }
    finally { $memory.Dispose() }
}

function New-SampleArchiveBytes($Definition) {
    $manifest = [ordered]@{
        '$schema' = 'https://raw.githubusercontent.com/HasinthaAttanayake/NEMSweep/main/schema/manifest-v2.json'
        schemaVersion = 2
        bundleId = 'bundle'
        name = $Definition.Name
        period = [ordered]@{ start = $Definition.Start; end = $Definition.End }
        regions = @($Definition.Regions | ForEach-Object {
            [ordered]@{ regionId = $_.Id; weatherDirectory = $_.Directory }
        })
    }
    $json = ($manifest | ConvertTo-Json -Depth 10).Replace("`r`n", "`n") + "`n"
    $entries = [ordered]@{}
    $entries['manifest.json'] = $script:Utf8.GetBytes($json)
    $entries['demand/operational-demand-hh/synthetic-demand.zip'] = New-SampleZipBytes @{
        'operational-demand.csv' = (New-SampleDemandBytes $Definition)
    }
    for ($index = 0; $index -lt $Definition.Regions.Count; $index++) {
        $region = $Definition.Regions[$index]
        $entries["weather/$($region.Directory)/synthetic-typical-year.epw"] = New-SampleWeatherBytes $Definition $region $index
    }
    return ,(New-SampleZipBytes $entries)
}

function Get-SampleSha256([byte[]] $Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Assert-SamplePin($Pin, [byte[]] $Bytes) {
    if ($Bytes.LongLength -ne $Pin.length -or (Get-SampleSha256 $Bytes) -cne $Pin.sha256) {
        throw "Candidate $($Pin.name) differs from its checked-in length/SHA256. Do not replace or publish it."
    }
}
