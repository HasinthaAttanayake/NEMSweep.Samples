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
            Asset = 'advanced-v2.zip'; Name = 'Australian NEM FY2026 (1 July 2025-30 June 2026): AEMO operational demand and original TMYx 2011-2025 EPW weather'
            Start = '2025-07-01T00:00:00+10:00'; End = '2026-07-01T00:00:00+10:00'
            Regions = @(
                [pscustomobject]@{ Id = 'NSW1'; Directory = 'NSW1' },
                [pscustomobject]@{ Id = 'QLD1'; Directory = 'QLD1' },
                [pscustomobject]@{ Id = 'SA1'; Directory = 'SA1' },
                [pscustomobject]@{ Id = 'TAS1'; Directory = 'TAS1' },
                [pscustomobject]@{ Id = 'VIC1'; Directory = 'VIC1' }
            )
        }
    )
}

function Get-SampleDemandMw($Definition, $Region, [DateTimeOffset] $IntervalStart) {
    if ($Definition.Asset -ne 'simple-v2.zip') { throw 'Only Simple demand may be generated; Advanced must preserve original inputs.' }
    if ($IntervalStart.Hour -ge 8 -and $IntervalStart.Hour -lt 20) { return 60 }
    return 30
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

function Get-ReviewedAdvancedInputNames {
    for ($date = [DateTime]::new(2025, 7, 6); $date -le [DateTime]::new(2026, 7, 5); $date = $date.AddDays(7)) {
        'demand/operational-demand-hh/PUBLIC_ACTUAL_OPERATIONAL_DEMAND_HH_' + $date.ToString('yyyyMMdd', $script:Invariant) + '.zip'
    }
    'demand/operational-demand-hh/PUBLIC_ARCHIVE#DEMANDOPERATIONALACTUAL#FILE01#202507010000.zip'
    'weather/NSW1/solar/AUS_NSW_Dubbo.City.Rgnl.AP.957190_TMYx.2011-2025.epw'
    'weather/NSW1/wind/AUS_NSW_Armidale.AP.957730_TMYx.2011-2025.epw'
    'weather/QLD1/solar/AUS_QLD_Gladstone.AP.943810_TMYx.2011-2025.epw'
    'weather/QLD1/wind/AUS_QLD_Kingaroy.AP.945490_TMYx.2011-2025.epw'
    'weather/SA1/AUS_SA_Port.Augusta.AP.956660_TMYx.2011-2025.epw'
    'weather/TAS1/AUS_TAS_Cape.Grim.Baseline.Air.Pollution.Stn.959540_TMYx.2011-2025.epw'
    'weather/VIC1/AUS_VIC_Ballarat.AP.948520_TMYx.2011-2025.epw'
}

function Assert-ReviewedAdvancedInputNames([string[]] $Names) {
    [string[]]$expected = @(Get-ReviewedAdvancedInputNames)
    [Array]::Sort($expected, [StringComparer]::Ordinal)
    [Array]::Sort($Names, [StringComparer]::Ordinal)
    if ([string]::Join("`n", $Names) -cne [string]::Join("`n", $expected)) {
        throw "Advanced file set differs from the reviewed demand/weather paths (expected $($expected.Count) inputs)."
    }
}

function Get-AdvancedInputEntries([string] $SourceBundleDirectory) {
    if (!$SourceBundleDirectory) { throw 'Advanced requires the original FY2026 source bundle; generated data is not a substitute.' }
    $root = [IO.Path]::GetFullPath($SourceBundleDirectory).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $manifest = Get-Content -LiteralPath (Join-Path $root 'manifest.json') -Raw | ConvertFrom-Json
    $definition = @(Get-SampleDefinitions)[1]
    if ($manifest.schemaVersion -ne 2 -or $manifest.period.start -cne $definition.Start -or $manifest.period.end -cne $definition.End -or $manifest.regions.Count -ne 5) {
        throw 'The source must be a format-2 Australian NEM FY2026 bundle with the expected UTC+10 period.'
    }
    foreach ($region in $definition.Regions) {
        $mapping = @($manifest.regions | Where-Object { $_.regionId -ceq $region.Id -and $_.weatherDirectory -ceq $region.Directory })
        if ($mapping.Count -ne 1) { throw 'The source region/weather mappings differ from the Australian NEM bundle.' }
    }
    $entries = [ordered]@{}
    $files = @(Get-ChildItem -LiteralPath (Join-Path $root 'demand\operational-demand-hh') -File -Recurse -Filter '*.zip')
    $files += @(Get-ChildItem -LiteralPath (Join-Path $root 'weather') -File -Recurse -Filter '*.epw')
    foreach ($file in ($files | Sort-Object FullName)) {
        $name = $file.FullName.Substring($root.Length + 1).Replace('\', '/')
        if ($name -notmatch '^(demand/operational-demand-hh/[A-Za-z0-9_.#-]+\.zip|weather/(?:[A-Za-z0-9_-]+/)+[A-Za-z0-9_.-]+\.epw)$' -or $entries.Contains($name)) {
            throw "Unexpected or colliding original input path: $name"
        }
        $entries[$name] = [IO.File]::ReadAllBytes($file.FullName)
    }
    Assert-ReviewedAdvancedInputNames @($entries.Keys)
    return ,$entries
}

function New-SampleArchiveBytes($Definition, [Collections.IDictionary] $AdvancedInputs) {
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
    if ($Definition.Asset -eq 'advanced-v2.zip') {
        if (!$AdvancedInputs -or $AdvancedInputs.Count -eq 0) { throw 'Advanced requires original input bytes; generated data is not a substitute.' }
        foreach ($name in $AdvancedInputs.Keys) { $entries[$name] = $AdvancedInputs[$name] }
    } else {
        $entries['demand/operational-demand-hh/synthetic-demand.zip'] = New-SampleZipBytes @{
            'operational-demand.csv' = (New-SampleDemandBytes $Definition)
        }
        $region = $Definition.Regions[0]
        $entries["weather/$($region.Directory)/synthetic-typical-year.epw"] = New-SampleWeatherBytes $Definition $region 0
    }
    return ,(New-SampleZipBytes $entries)
}

function Get-SampleSha256([byte[]] $Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Assert-AdvancedInputsWithCli([byte[]] $Bytes, [string] $CliAssemblyPath) {
    $root = Join-Path ([IO.Path]::GetTempPath()) ("nemsweep-original-inputs-" + [Guid]::NewGuid().ToString('N'))
    $bundle = Join-Path $root 'bundle'
    [IO.Directory]::CreateDirectory($bundle) | Out-Null
    $memory = [IO.MemoryStream]::new($Bytes, $false)
    $archive = [IO.Compression.ZipArchive]::new($memory, [IO.Compression.ZipArchiveMode]::Read)
    try {
        foreach ($entry in $archive.Entries) {
            if ($entry.FullName -notmatch '^(manifest\.json|demand/operational-demand-hh/[A-Za-z0-9_.#-]+\.zip|weather/(?:[A-Za-z0-9_-]+/)+[A-Za-z0-9_.-]+\.epw)$') {
                throw "Unexpected original-input validation entry: $($entry.FullName)"
            }
            $path = Join-Path $bundle $entry.FullName.Replace('/', '\')
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path)) | Out-Null
            $input = $entry.Open()
            $output = [IO.File]::Create($path)
            try { $input.CopyTo($output) }
            finally { $output.Dispose(); $input.Dispose() }
        }
        & dotnet $CliAssemblyPath --validate-inputs $bundle
        if ($LASTEXITCODE -ne 0) { throw 'Original Advanced inputs failed complete bundle validation in the compatible CLI.' }
    }
    finally {
        $archive.Dispose()
        $memory.Dispose()
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}

function Assert-SamplePin($Pin, [byte[]] $Bytes) {
    if ($Bytes.LongLength -ne $Pin.length -or (Get-SampleSha256 $Bytes) -cne $Pin.sha256) {
        throw "Candidate $($Pin.name) differs from its checked-in length/SHA256. Do not replace or publish it."
    }
}
