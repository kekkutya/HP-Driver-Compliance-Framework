<#
.SYNOPSIS
    Synchronizes current HP-DCF documentation version references with version.json.

.DESCRIPTION
    Updates explicitly maintained current or baseline version references in the
    repository documentation from version.json. Historical references and example
    values are intentionally not changed. Use -Check to verify without modifying.
#>

[CmdletBinding()]
param([switch]$Check)

$ErrorActionPreference = "Stop"
$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$VersionFile = Join-Path $RepositoryRoot "version.json"

if (-not (Test-Path -LiteralPath $VersionFile -PathType Leaf)) {
    throw "version.json was not found: $VersionFile"
}

$VersionInfo = (
    [System.IO.File]::ReadAllText(
        $VersionFile,
        [System.Text.Encoding]::UTF8
    )
) | ConvertFrom-Json
$FrameworkVersion = [string]$VersionInfo.FrameworkVersion
$DriverEvaluatorVersion = [string]$VersionInfo.Components.DriverEvaluator
$DriverDeployerVersion = [string]$VersionInfo.Components.DriverDeployer
$AdministrativeTemplateVersion = [string]$VersionInfo.Artifacts.AdministrativeTemplate

$Versions = @(
    @{ Name = "FrameworkVersion"; Value = $FrameworkVersion }
    @{ Name = "DriverEvaluator"; Value = $DriverEvaluatorVersion }
    @{ Name = "DriverDeployer"; Value = $DriverDeployerVersion }
    @{ Name = "AdministrativeTemplate"; Value = $AdministrativeTemplateVersion }
)

foreach ($Version in $Versions) {
    if ([string]::IsNullOrWhiteSpace($Version.Value)) {
        throw "Version value [$($Version.Name)] is missing from version.json."
    }
}

function New-VersionRule {
    param(
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$Replacement
    )

    [pscustomobject]@{
        Pattern = $Pattern
        Replacement = $Replacement
    }
}

$Documents = @(
    @{
        Path = "README.md"
        Rules = @(
            New-VersionRule -Pattern '^Current baseline: \*\*Framework [^*]+\*\*, \*\*DriverEvaluator [^*]+\*\*, \*\*DriverDeployer [^*]+\*\*\.\r?$' -Replacement "Current baseline: **Framework $FrameworkVersion**, **DriverEvaluator $DriverEvaluatorVersion**, **DriverDeployer $DriverDeployerVersion**."
        )
    }
    @{
        Path = "docs\README.md"
        Rules = @(
            New-VersionRule -Pattern '^The documentation describes the \*\*v[^*]+\*\* framework baseline \(DriverEvaluator [^,]+, DriverDeployer [^)]+\)\.\r?$' -Replacement "The documentation describes the **v$FrameworkVersion** framework baseline (DriverEvaluator $DriverEvaluatorVersion, DriverDeployer $DriverDeployerVersion)."
        )
    }
    @{
        Path = "docs\en\README.md"
        Rules = @(
            New-VersionRule -Pattern '^This directory contains the canonical English technical documentation for \*\*HP Driver Compliance Framework \(HP-DCF\) v[^*]+\*\*\.\r?$' -Replacement "This directory contains the canonical English technical documentation for **HP Driver Compliance Framework (HP-DCF) v$FrameworkVersion**."
        )
    }
    @{
        Path = "docs\hu\README.md"
        Rules = @(
            New-VersionRule -Pattern '^Ez a könyvtár a \*\*HP Driver Compliance Framework \(HP-DCF\) v[^*]+\*\* magyar műszaki dokumentációját tartalmazza\.' -Replacement "Ez a könyvtár a **HP Driver Compliance Framework (HP-DCF) v$FrameworkVersion** magyar műszaki dokumentációját tartalmazza."
        )
    }
    @{
        Path = "docs\en\configuration.md"
        Rules = @(
            New-VersionRule -Pattern '^This document describes the effective configuration model of HP-DCF v[0-9]+\.[0-9]+\.[0-9]+\.\r?$' -Replacement "This document describes the effective configuration model of HP-DCF v$FrameworkVersion."
        )
    }
    @{
        Path = "docs\hu\configuration.md"
        Rules = @(
            New-VersionRule -Pattern '^Ez a dokumentum a HP-DCF v[0-9]+\.[0-9]+\.[0-9]+ effektív konfigurációs modelljét írja le\.\r?$' -Replacement "Ez a dokumentum a HP-DCF v$FrameworkVersion effektív konfigurációs modelljét írja le."
        )
    }
    @{
        Path = "docs\en\deployment.md"
        Rules = @(
            New-VersionRule -Pattern '^`version\.json` independently tracks framework and component versions\. For v[0-9]+\.[0-9]+\.[0-9]+:\r?$' -Replacement ('`version.json` independently tracks framework and component versions. For v' + $FrameworkVersion + ':')
            New-VersionRule -Pattern '^Framework\s*[0-9]+\.[0-9]+\.[0-9]+\r?$' -Replacement "Framework       $FrameworkVersion"
            New-VersionRule -Pattern '^DriverEvaluator\s*[0-9]+\.[0-9]+\.[0-9]+\r?$' -Replacement "DriverEvaluator $DriverEvaluatorVersion"
            New-VersionRule -Pattern '^DriverDeployer\s*[0-9]+\.[0-9]+\.[0-9]+\r?$' -Replacement "DriverDeployer  $DriverDeployerVersion"
            New-VersionRule -Pattern '^Administrative Template\s*[0-9]+\.[0-9]+\.[0-9]+\r?$' -Replacement "Administrative Template  $AdministrativeTemplateVersion"
        )
    }
    @{
        Path = "docs\hu\deployment.md"
        Rules = @(
            New-VersionRule -Pattern '^v[0-9]+\.[0-9]+\.[0-9]+:\r?$' -Replacement "v${FrameworkVersion}:"
            New-VersionRule -Pattern '^Framework\s*[0-9]+\.[0-9]+\.[0-9]+\r?$' -Replacement "Framework       $FrameworkVersion"
            New-VersionRule -Pattern '^DriverEvaluator\s*[0-9]+\.[0-9]+\.[0-9]+\r?$' -Replacement "DriverEvaluator $DriverEvaluatorVersion"
            New-VersionRule -Pattern '^DriverDeployer\s*[0-9]+\.[0-9]+\.[0-9]+\r?$' -Replacement "DriverDeployer  $DriverDeployerVersion"
            New-VersionRule -Pattern '^Administrative Template\s*[0-9]+\.[0-9]+\.[0-9]+\r?$' -Replacement "Administrative Template  $AdministrativeTemplateVersion"
        )
    }
)

$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$ChangesRequired = $false

foreach ($Document in $Documents) {
    $DocumentPath = Join-Path $RepositoryRoot $Document.Path

    if (-not (Test-Path -LiteralPath $DocumentPath -PathType Leaf)) {
        throw "Documentation target was not found: $($Document.Path)"
    }

    $OriginalContent = [System.IO.File]::ReadAllText(
        $DocumentPath,
        [System.Text.Encoding]::UTF8
    )
    $UpdatedContent = $OriginalContent
    $DocumentChanged = $false

    foreach ($Rule in $Document.Rules) {
        $Matches = [regex]::Matches(
            $UpdatedContent,
            $Rule.Pattern,
            [System.Text.RegularExpressions.RegexOptions]::Multiline
        )

        if ($Matches.Count -ne 1) {
            throw "Expected exactly one version reference in [$($Document.Path)], found [$($Matches.Count)]. Pattern: [$($Rule.Pattern)]"
        }

        $Match = $Matches[0]

        if ($Match.Value.TrimEnd("`r") -eq $Rule.Replacement) {
            continue
        }

        $UpdatedContent =
            $UpdatedContent.Substring(0, $Match.Index) +
            $Rule.Replacement +
            $UpdatedContent.Substring($Match.Index + $Match.Length)

        $DocumentChanged = $true
    }

    if (-not $DocumentChanged) {
        Write-Host "Current:     $($Document.Path)"
        continue
    }

    $ChangesRequired = $true

    if ($Check) {
        Write-Host "Out of sync: $($Document.Path)"
        continue
    }

    [System.IO.File]::WriteAllText($DocumentPath, $UpdatedContent, $Utf8NoBom)
    Write-Host "Updated:     $($Document.Path)"
}

if ($Check -and $ChangesRequired) {
    throw "Documentation version references are not synchronized with version.json."
}

if ($Check) {
    Write-Host "Documentation version references are synchronized."
}
else {
    Write-Host "Documentation version synchronization completed."
}
