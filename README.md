# NEMSweep.Samples

**No downloadable data release has been published yet.** This public repository
contains the maintainer recipes and candidate checksums, not the sample ZIPs.
The initial samples PR has merged. Review and merge the **corrected Advanced
input/provenance PR**, and confirm source redistribution rights, before publication.
These data-only starter inputs
are separate from the [NEMSweep CLI](https://github.com/HasinthaAttanayake/NEMSweep).

## For sample users: no PowerShell required

You do **not** need to clone this repository or run its `.ps1` scripts to use the
samples. Once published, the normal paths are to download a ready-made ZIP or
use the compatible CLI's `--quick-start simple` / `--quick-start advanced`.

| Activity | Requirements | Platform considerations |
| --- | --- | --- |
| Download and extract a starter ZIP | Browser or HTTP downloader and a ZIP extractor | No PowerShell or .NET required; usable on Windows, Linux and macOS. |
| Prepare a study with CLI quick-start | Compatible NEMSweep CLI and .NET 10 runtime; SDK for a source build | Download, verification, extraction and ingestion run in .NET, not PowerShell. |
| Run a scenario or sweep | Compatible NEMSweep CLI, .NET runtime and prepared inputs | No PowerShell required; use your normal shell. |
| Regenerate, validate or publish with this repository's scripts | Windows PowerShell 5.1, .NET Framework 4.8.1 and a compatible built CLI; generation also needs the original input bundle; publication needs git/gh | Maintainer tooling, verified on Windows only. PowerShell 7 on Linux/macOS is not a verified replacement. |

The CLI is separate from these data-production scripts. A Windows user without
PowerShell can still download the ZIPs and use the CLI. PowerShell 7 is available
on other operating systems, but these recipes and their exact pinned archive
bytes have **not** been validated there.

The quick-start feature currently requires the reviewed CLI source build; it is
not in the older `0.1.0` NuGet package. See the
[CLI starter guide](https://github.com/HasinthaAttanayake/NEMSweep/blob/feat/github-quickstart/docs/guide/synthetic-starters.md)
for preparation and run instructions.

## Where are the ZIPs?

The intended public home is **[GitHub Releases](https://github.com/HasinthaAttanayake/NEMSweep.Samples/releases)**,
under the data release's **Assets** section, not the repository's file listing.
The assets will be named `simple-v2.zip` and `advanced-v2.zip`. GitHub's automatic
**Source code (zip)** download contains the recipes, not the generated datasets.

Until the reviewed release is published, the candidates are local only. Running
the maintainer generation command below writes them to the selected output
directory, for example `generated/simple-v2.zip` and `generated/advanced-v2.zip`.
Neither this Git checkout nor the validation workflow provides hosted ZIP
downloads: generated assets are gitignored and CI does not upload them.
The planned URLs below return 404 until publication; cloning the repository does
not fetch the datasets.

## Proposed data release

The samples-only tag is **`v2026.10.1`**. It is not a CLI version. These are planned
URLs, **pending publication after user review and merge**; they are not currently
downloadable assets:

| Starter | Planned URL | Period (fixed UTC+10, end exclusive) |
| --- | --- | --- |
| Simple | `https://github.com/HasinthaAttanayake/NEMSweep.Samples/releases/download/v2026.10.1/simple-v2.zip` | 2025-01-01 through 2026-01-01 |
| Advanced | `https://github.com/HasinthaAttanayake/NEMSweep.Samples/releases/download/v2026.10.1/advanced-v2.zip` | 2025-07-01 through 2026-07-01 (FY2026) |

The checked-in [release-candidate.json](release-candidate.json) records exact byte
lengths and SHA256 hashes; [checksums.txt](checksums.txt) gives the same pins in
standard checksum-list format. Neither ZIPs nor large generated data are committed.
Do not replace an existing pinned asset with different bytes; revise and review the
recipe and use a new data tag for future data changes.

Each outer archive has raw input entries **at its root**, not inside a `bundle/`
prefix. The CLI extracts it into a directory named `bundle`:

```text
manifest.json
demand/operational-demand-hh/<demand-archive>.zip
weather/<weatherDirectory>/<original-or-synthetic>.epw
```

Simple has one generated demand ZIP and EPW. Advanced preserves 54 original
AEMO ZIPs (including their nested interval archives) and seven original EPWs.
NSW1 and QLD1 each retain separate `solar/` and `wind/` subdirectories.
There are no
executables, scripts, scenario/sweep settings, generation workbooks, ingested JSON
artifacts or historical generation data in these downloads. The required manifest
is the only JSON file. Advanced's original inputs are copied, not regenerated.

## Geography, period and source provenance

**Simple is synthetic. Advanced uses the original real AEMO demand and original
EPW files.** Both are onboarding examples with separately supplied scenario
assumptions, not forecasts, calibrated models or certified results.

* **Simple:** `Island-X` maps to `station-01`. Every half-hour interval whose
  **start** is between 08:00 inclusive and 20:00 exclusive has interval-average
  demand 60 MW; all other intervals have 30 MW. CSV labels are interval **ends**,
  so the last label is 2026/01/01 00:00:00. The shape is adapted from upstream
  `examples/custom-grid/Generate-SyntheticGrid.ps1`, revision
  `766316fbe1ce8bc965d2ed38e5500aa1f8c761e0`. Upstream configuration-generation
  behavior is deliberately not included.
* **Advanced: Australian National Electricity Market (NEM), FY2026**
  (1 July 2025 through 30 June 2026). The manifest explicitly identifies the
  geography, demand period and weather provenance. All 54 original AEMO
  `ACTUAL_OPERATIONAL_DEMAND_HH` ZIPs are copied byte-for-byte from the original
  format-2 core bundle. Raw source values are preserved, including negative SA1
  records; normal CLI ingestion applies its existing nonnegative-demand handling.
  `NSW1`, `QLD1`, `SA1`, `TAS1`, `VIC1` retain their identically named weather mappings.
  The final interval-end demand label is 2026/07/01 00:00:00.
* Each region has **17,520 demand intervals**, with no gaps or duplicates.
  There are 17,520 Simple demand records and 87,600 Advanced records.
* **Advanced weather is the seven original TMYx 2011-2025 EPWs**, with original
  filenames, headers, roles and bytes. Their headers identify NCEI ISD/ERA5
  records and downloads from [Climate.Onebuilding.org](https://climate.onebuilding.org/).
  The source period is 2011-2025; months are selected from different historical
  years to form typical-year profiles. **This is not weather measured in FY2026.**
  The CLI replays those profiles across the FY2026 demand/scenario period.
  Each source EPW has 8,760 hourly records. The original SA1 EPW uses **UTC+09:30**;
  the other six use **UTC+10**. The existing CLI normalizes weather to the run's
  fixed **UTC+10** market time; the original headers/bytes remain unchanged.
  Neither source typical-year profiles nor the run apply daylight saving.
* **Simple weather** is an illustrative non-leap year **2001**. Its EPW uses
  the upstream generator's 22-field subset consumed by NEMSweep, not a
  claim of completeness for unrelated EPW consumers. Hours are 1–24. Daylight
  hours starting at 06:00–18:00 have GHI/DNI/DHI of 500/600/100 Wh/m²;
  nighttime values are zero. Simple has constant 25°C and 5 m/s wind.
  Its coordinates are illustrative, not a measured station.

| Advanced region | Solar EPW site | Wind EPW site |
| --- | --- | --- |
| NSW1 | Dubbo City Regional Airport | Armidale Airport |
| QLD1 | Gladstone Airport | Kingaroy Airport |
| SA1 | Port Augusta Airport | Same file |
| TAS1 | Cape Grim Baseline Air Pollution Station | Same file |
| VIC1 | Ballarat Airport | Same file |

Simple CSV/EPW headers explicitly identify synthetic data. Advanced retains the
original AEMO and EPW provenance. The complete original-file inventory and each
file's length/SHA256 are recorded in [release-candidate.json](release-candidate.json).
Provenance is kept in source inputs rather than inventing unsupported manifest
properties. The [BSD-3-Clause license](LICENSE.md) covers this recipe and its
synthetic data, preserving upstream attribution. It does **not** cover AEMO or
third-party EPW datasets. Before publishing Advanced, an authorized maintainer
must separately review and confirm redistribution rights and required attribution
for **both** source datasets. No revised real-data release is authorized here.

The [licence's third-party attribution notice](LICENSE.md#third-party-advanced-input-data)
cites the EPW creators and links all seven original publisher downloads.
All seven EPWs remain included in Advanced, unaltered; the notice does not
relicense those files under BSD-3-Clause.

## Maintainers: generate and validate locally

**Supported maintainer platform: Windows only**, using Windows PowerShell 5.1
and .NET Framework 4.8.1. Linux/macOS and PowerShell 7 regeneration are not
currently supported or tested. This limitation applies to producing, validating
and publishing assets with these scripts, not to consuming the sample data.

These `.ps1` scripts build and verify release assets; they are **not user setup
scripts**. They require Windows PowerShell 5.1 and .NET Framework 4.8.1.
Generation requires the original format-2 FY2026 core bundle and a compatible
CLI assembly (`nemsweep.dll`). Build that CLI with the .NET 10 SDK, or provide an
already built assembly and the .NET 10 runtime. Raw inputs are external to this
repository; the inventory hashes verify that the reviewed originals were used.
The pinned recipe was verified with **Windows PowerShell 5.1 and .NET
Framework 4.8.1 (installed version 4.8.09221)**. Different PowerShell/.NET versions
may serialize ZIP/JSON bytes differently; the scripts fail rather than silently
accept different hashes. Cross-platform regeneration is not currently verified;
installing PowerShell 7 alone does not establish compatibility. Run from this
repository in Windows PowerShell:

```powershell
$source = 'C:\path\to\NEMSweep\data\nemsweep-inputs-v2'
$cli = 'C:\path\to\NEMSweep\NEMSweep.CLI\bin\Release\net10.0\nemsweep.dll'
.\scripts\Generate-Samples.ps1 -OutputDirectory .\generated -SourceBundleDirectory $source -CliAssemblyPath $cli
.\scripts\Validate-Samples.ps1 -CandidateDirectory .\generated -CliAssemblyPath $cli
.\scripts\Test-Samples.ps1 -VerificationDirectory .\.repro-check -CliAssemblyPath $cli -SourceBundleDirectory $source
```

Generation requires a directory without either candidate asset; it refuses to
overwrite files. Normal generation checks against the checked-in pins **before**
writing each asset. Generated text uses UTF-8 without BOM, LF endings and a final newline.
Original Advanced ZIP/EPW bytes are never reencoded. Generated ZIP layers use
`System.IO.Compression`, `NoCompression`, ordinal entry order,
zero external attributes and the fixed timestamp 1980-01-01 00:00:00. There are no
current dates, random numbers, host paths or culture-dependent numbers in assets.
ZIP entry names use `/` as required by the portable ZIP format.

`-InitializeCandidateMetadata` is only for the initial maintainer bootstrap when
**neither** metadata file exists; it cannot overwrite existing pins. It is not
part of routine regeneration or publication. Even initialization requires the
reviewed set of 54 AEMO archive filenames and seven EPW paths, including the
separate NSW1/QLD1 solar/wind roles; truncated or substituted inventories are rejected.

Validation checks hashes/lengths, the allowlisted layout, manifest/mappings,
fixed UTC+10 periods and deterministic generated ZIPs. Simple is checked against
every generated demand/weather value. Advanced checks every original-file pin
and calls the compatible CLI's complete demand/weather validation, reusing its
nested AEMO archive parser rather than duplicating it. Tests exercise
deterministic regeneration, unchanged Simple pins, byte preservation, missing/corrupt inputs,
injected executable entries, wrong mappings,
incomplete coverage and weather offsets, and mock git/gh to test publication
refusals. Tests make **no network calls** and do not publish. Their newly created
verification directory is removed unless `-KeepVerificationDirectory` is supplied.

Without `-SourceBundleDirectory`, tests build explicitly synthetic source fixtures
in an isolated recipe directory. They cover the same five-region/seven-EPW role
layout but **do not certify the real Advanced candidate**. Tests first verify that
production initialization refuses those fixtures, then substitute an explicit
fixture allowlist only in the disposable test recipe. Production scripts have no
fixture-bypass flag. The command above uses
the actual original source bundle; independently run `Validate-Samples.ps1`
against the checked-in release pins before publication.

### Continuous integration

The [validation workflow](.github/workflows/validate-samples.yml) runs on pushes
and pull requests using `windows-2025`, explicitly selecting Windows PowerShell
5.1 (`powershell`, not `pwsh`) and checking for .NET Framework 4.8.1. It checks out
a pinned compatible CLI revision and builds it, then runs hermetic fixture tests:

```powershell
.\scripts\Test-Samples.ps1 -VerificationDirectory .\.repro-check -CliAssemblyPath $cli
```

After CLI checkout/build, testing is offline. It covers fixture regeneration,
source-byte preservation, unchanged Simple pins, full-period checks, mutations
and mocked publication gates, then verifies cleanup and an unchanged checkout.
The workflow has only `contents: read`, does not persist checkout credentials,
clears GitHub token environment variables for tests, and has no publication
steps or uploaded candidate assets. Runner patch versions can change; exact
Simple SHA256 pins still have to match and are never updated automatically.
Real Advanced regeneration/validation is an explicit local integration check:
CI neither obtains nor uploads the third-party originals.

## Maintainer publication: explicit approval required

**Do not run this during candidate preparation.** Publication additionally needs
`git`, an authenticated `gh` with release-write permission, and a clean checkout
of merged `main` whose SHA is the explicitly reviewed commit and current remote
main tip. The SHA must be the merge commit of a merged samples PR (normal merge
or squash merge; rebase-only history does not satisfy this gate).

After review, merge and CLI ingestion validation, an authorized maintainer may run:

```powershell
.\scripts\Publish-Samples.ps1 `
  -CandidateDirectory C:\path\to\reviewed-candidates `
  -ReviewedMainCommit <full-reviewed-main-commit-sha> `
  -CliAssemblyPath $cli `
  -ConfirmSourceRedistributionRights `
  -PublishReviewedCandidates
```

Omitting either publication approval or source-rights confirmation refuses publication. Feature branches,
detached HEADs, dirty trees, unreviewed/non-main commits, the wrong origin, absent
or hash-mismatched candidates, mismatched tags and existing releases are refused.
The publisher does not regenerate inputs, upload with `--clobber`, push main, or
merge a PR. `gh release create` targets the reviewed main commit; if needed GitHub
creates that data tag. An existing tag must be lightweight and point at that SHA.
License/attribution and checksums are included in release notes beside the two
raw-input assets. An interrupted publication requires manual review; the script
does not silently replace or repair an existing release.

## Input format references

* [NEMSweep input bundle guide](https://github.com/HasinthaAttanayake/NEMSweep/blob/main/docs/guide/input-bundles.md):
  manifest layout, interval-end demand convention and offset handling.
* [Manifest v2 schema](https://raw.githubusercontent.com/HasinthaAttanayake/NEMSweep/main/schema/manifest-v2.json).
* [AEMO MMS data model](https://visualisations.aemo.com.au/aemo/nemweb/MMSDataModelReport/Electricity/MMS%20Data%20Model%20Report.htm):
  `OPERATIONAL_DEMAND` record naming/shape for Advanced's original demand archives.
* [EnergyPlus EPW data dictionary](https://bigladdersoftware.com/epx/docs/24-2/auxiliary-programs/energyplus-weather-file-epw-data-dictionary.html):
  header/field conventions; Simple implements NEMSweep's consumed subset, Advanced
  preserves the original full EPWs.
