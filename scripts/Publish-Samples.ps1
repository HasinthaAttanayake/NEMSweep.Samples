[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $CandidateDirectory,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{40}$')][string] $ReviewedMainCommit,
    [Parameter(Mandatory = $true)][string] $CliAssemblyPath,
    [switch] $ConfirmSourceRedistributionRights,
    [switch] $PublishReviewedCandidates
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (!$PublishReviewedCandidates) { throw 'Publication is disabled. Review and merge the samples PR before explicitly supplying -PublishReviewedCandidates.' }
$repoRoot = Split-Path $PSScriptRoot -Parent
function Invoke-GitChecked([string[]] $Arguments) {
    $result = & git -C $repoRoot @Arguments
    if ($LASTEXITCODE -ne 0) { throw "git failed: $Arguments" }
    return $result
}
function Invoke-GhChecked([string[]] $Arguments) {
    $result = & gh @Arguments
    if ($LASTEXITCODE -ne 0) { throw "gh failed: $Arguments" }
    return $result
}
$repository = 'HasinthaAttanayake/NEMSweep.Samples'
$tag = 'v2026.10.1'
if ((Invoke-GitChecked @('branch', '--show-current')) -cne 'main') { throw 'Publication requires the merged main branch, not a feature branch or detached HEAD.' }
if (@(Invoke-GitChecked @('status', '--porcelain')).Count -ne 0) { throw 'Publication requires a clean working tree.' }
if ((Invoke-GitChecked @('rev-parse', 'HEAD')) -cne $ReviewedMainCommit) { throw 'HEAD differs from the explicitly reviewed main commit.' }
$origin = Invoke-GitChecked @('remote', 'get-url', 'origin')
if ($origin -cne "https://github.com/$repository.git" -and $origin -cne "git@github.com:$repository.git") { throw 'Unexpected origin; publication is restricted to NEMSweep.Samples.' }
$remoteMain = (Invoke-GhChecked @('api', "repos/$repository/commits/main")) | ConvertFrom-Json
if ($remoteMain.sha -cne $ReviewedMainCommit) { throw 'Reviewed commit is not the current remote main tip.' }
$pulls = (Invoke-GhChecked @('api', "repos/$repository/commits/$ReviewedMainCommit/pulls")) | ConvertFrom-Json
$merged = @($pulls | Where-Object {
    $_.merged_at -and $_.base.ref -ceq 'main' -and $_.base.repo.full_name -ceq $repository -and $_.merge_commit_sha -ceq $ReviewedMainCommit
})
if ($merged.Count -eq 0) { throw 'The reviewed main commit must be the merge commit of a merged samples pull request.' }

if (!$ConfirmSourceRedistributionRights) { throw 'Advanced contains third-party AEMO demand and EPW weather. Confirm redistribution rights and attribution for both before publication with -ConfirmSourceRedistributionRights.' }
& (Join-Path $PSScriptRoot 'Validate-Samples.ps1') -CandidateDirectory $CandidateDirectory -CliAssemblyPath $CliAssemblyPath
$metadata = Get-Content -LiteralPath (Join-Path $repoRoot 'release-candidate.json') -Raw | ConvertFrom-Json
$refs = (Invoke-GhChecked @('api', "repos/$repository/git/matching-refs/tags/$tag")) | ConvertFrom-Json
foreach ($ref in $refs) {
    if ($ref.ref -ceq "refs/tags/$tag" -and ($ref.object.type -cne 'commit' -or $ref.object.sha -cne $ReviewedMainCommit)) {
        throw 'Existing tag must be a lightweight tag at the reviewed main commit.'
    }
}
$releases = (Invoke-GhChecked @('api', '--paginate', '--slurp', "repos/$repository/releases?per_page=100")) | ConvertFrom-Json
foreach ($page in $releases) {
    if (@($page | Where-Object { $_.tag_name -ceq $tag }).Count -gt 0) { throw 'Release already exists. Never replace pinned public assets.' }
}
$license = Get-Content -LiteralPath (Join-Path $repoRoot 'LICENSE.md') -Raw
$checksums = Get-Content -LiteralPath (Join-Path $repoRoot 'checksums.txt') -Raw
$notes = "NEMSweep schema-v2 starter inputs. Simple is synthetic. Advanced represents Australia's NEM FY2026 (1 July 2025-30 June 2026), preserving real AEMO operational demand and the original TMYx 2011-2025 EPW weather files. Typical-year weather is not measured FY2026 weather. Scenario assumptions are examples, not forecasts or certified results.`n`nReviewed main commit: $ReviewedMainCommit`n`nSHA256:`n$checksums`nBSD-3-Clause covers the recipes and synthetic data, not the third-party AEMO demand or EPW weather. Upstream redistribution rights and attribution for both were separately confirmed by the publisher; see the reviewed repository README for provenance.`n$license"
$arguments = @('release', 'create', $tag, '--repo', $repository, '--target', $ReviewedMainCommit,
    '--title', 'Simple and Australian NEM FY2026 input bundles v2026.10.1', '--notes', $notes)
foreach ($asset in $metadata.assets) { $arguments += Join-Path ([IO.Path]::GetFullPath($CandidateDirectory)) $asset.name }
Invoke-GhChecked $arguments
