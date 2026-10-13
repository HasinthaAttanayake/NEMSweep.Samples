# NEMSweep.Samples

**Local release candidates only. Nothing has been published.** Review and merge the
samples pull request before authorizing publication. These data-only starter inputs
are separate from the [NEMSweep CLI](https://github.com/HasinthaAttanayake/NEMSweep).

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
demand/operational-demand-hh/synthetic-demand.zip
weather/<weatherDirectory>/synthetic-typical-year.epw
```

The nested demand ZIP contains only `operational-demand.csv`. There are no
executables, scripts, scenario/sweep settings, generation workbooks, ingested JSON
artifacts, or real source datasets in these downloads. The required manifest is
the only JSON file. One EPW per region supplies both solar and wind input roles.

## Synthetic, not measured

Both starters are generated from constants and calendar rules, without reading or
copying any AEMO archive, observed trace, or third-party EPW. They are onboarding
examples, not forecasts, calibrated NEM models, resource assessments or evidence
about real market behavior.

* **Simple:** `Island-X` maps to `station-01`. Every half-hour interval whose
  **start** is between 08:00 inclusive and 20:00 exclusive has interval-average
  demand 60 MW; all other intervals have 30 MW. CSV labels are interval **ends**,
  so the last label is 2026/01/01 00:00:00. The shape is adapted from upstream
  `examples/custom-grid/Generate-SyntheticGrid.ps1`, revision
  `766316fbe1ce8bc965d2ed38e5500aa1f8c761e0`. Upstream configuration-generation
  behavior is deliberately not included.
* **Advanced:** `NSW1`, `QLD1`, `SA1`, `TAS1`, `VIC1` map respectively to `nsw1`,
  `qld1`, `sa1`, `tas1`, `vic1`. Illustrative base demand is 7,500 / 6,000 / 1,500 /
  1,000 / 4,500 MW: NEM-scale constants, **not measured regional averages**.
  Demand equals base MW times a day/night factor (1.15 for 08:00–20:00,
  otherwise 0.85), season factor (1.10 for December–February and June–August,
  otherwise 0.95) and weekend factor (0.92, otherwise 1.00), rounded to integer
  MW away from zero. The final interval-end label is 2026/07/01 00:00:00.
* Each region has **17,520 demand intervals**, with no gaps or duplicates.
  There are 17,520 Simple demand records and 87,600 Advanced records.
* Weather is an illustrative non-leap typical year **2001**, 8,760 hourly records
  per region. It is replayed over the manifest period, including FY2026's year
  boundary, by the CLI. All EPW input time zones are **UTC+10**; neither manifest
  periods nor source weather apply daylight saving.
* EPW uses the upstream generator's 22-field subset consumed by NEMSweep, not a
  claim of completeness for unrelated EPW consumers. Hours are 1–24. Daylight
  hours starting at 06:00–18:00 have GHI/DNI/DHI of 500/600/100 Wh/m²;
  nighttime values are zero. Simple has constant 25°C and 5 m/s wind. Advanced
  temperatures are 22/26/23/15/20°C and wind speeds 5/4/6/7/5 m/s in region order.
  Coordinates are illustrative regional locations, not measured stations.

CSV provenance explicitly says `SYNTHETIC`; EPW `LOCATION` and comment headers say
synthetic and not measured. Manifest names also identify synthetic demonstrations.
Provenance is kept in source inputs rather than inventing unsupported manifest
properties. The [BSD-3-Clause license](LICENSE.md) covers this recipe and its
synthetic data, preserving upstream attribution. It does **not** cover AEMO or
third-party datasets, which are not redistributed here.

## Generate and validate locally

No CLI checkout, .NET SDK, Python, external data, download or package installation
is needed. The pinned recipe was verified with **Windows PowerShell 5.1 and .NET
Framework 4.8.1 (installed version 4.8.09221)**. Different PowerShell/.NET versions
may serialize ZIP/JSON bytes differently; the scripts fail rather than silently
accept different hashes. Run from this repository in Windows PowerShell:

```powershell
.\scripts\Generate-Samples.ps1 -OutputDirectory .\generated
.\scripts\Validate-Samples.ps1 -CandidateDirectory .\generated
.\scripts\Test-Samples.ps1 -VerificationDirectory .\.repro-check
```

Generation requires a directory without either candidate asset; it refuses to
overwrite files. Normal generation checks against the checked-in pins **before**
writing each asset. Text uses UTF-8 without BOM, LF endings and a final newline.
Both ZIP layers use `System.IO.Compression`, `NoCompression`, ordinal entry order,
zero external attributes and the fixed timestamp 1980-01-01 00:00:00. There are no
current dates, random numbers, host paths or culture-dependent numbers in assets.
ZIP entry names use `/` as required by the portable ZIP format.

`-InitializeCandidateMetadata` is only for the initial maintainer bootstrap when
**neither** metadata file exists; it cannot overwrite existing pins. It is not
part of routine regeneration or publication.

Validation checks hashes/lengths and the exact allowlisted root/nested layout,
manifest version and mappings, fixed UTC+10 periods, UTF-8/LF text, every demand
interval and value, every EPW date and consumed weather value, and deterministic
ZIP order/timestamps. Tests regenerate both candidates and require the existing
pins, exercise missing/corrupt inputs, injected executable entries, wrong mappings,
incomplete coverage and weather offsets, and mock git/gh to test publication
refusals. Tests make **no network calls** and do not publish. Their newly created
verification directory is removed unless `-KeepVerificationDirectory` is supplied.

Actual CLI ingestion/validation is a separate integration check performed by the
CLI project before publication; structural validation here is not a substitute.

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
  -PublishReviewedCandidates
```

Omitting the explicit switch always refuses publication. Feature branches,
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
  `OPERATIONAL_DEMAND` record naming/shape only; no AEMO data is included.
* [EnergyPlus EPW data dictionary](https://bigladdersoftware.com/epx/docs/24-2/auxiliary-programs/energyplus-weather-file-epw-data-dictionary.html):
  header/field conventions; these synthetic files implement NEMSweep's consumed subset.
