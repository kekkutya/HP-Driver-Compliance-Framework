<#
.SYNOPSIS
    HP Driver Compliance Framework - DriverDeployer

.DESCRIPTION
    Evaluates whether the latest complete Evaluation snapshot is eligible
    for deployment and, when eligible, hands the deployment to the PSADT package.

    DriverDeployer does not implement user interaction, defer handling or HPIA
    installation. Those responsibilities belong to the deployment PSADT.

    The PSADT owns the fixed HPIA deployment scope and parameters. DriverDeployer
    only determines whether deployment may start and whether an SPList is supplied.

.EXECUTION
    Normal:
      - Requires framework Enabled=1 and DriverDeployer Enabled=1.
      - Requires a complete valid Evaluation snapshot:
        .success + .manifest.json + .splist.txt.
      - Uses the latest valid snapshot, including occurrence-specific snapshots.
      - Does not redeploy a snapshot with a matching .deployed completion marker.
      - Applies ring eligibility.
      - Re-applies the current framework ExcludeSoftPaqs list immediately before
        deployment.
      - Creates Deployment.request.json and Deployment.splist.txt.
      - Creates Deployment.active and starts PSADT.

    -ForceRun:
      - Requires a complete valid Evaluation snapshot.
      - Bypasses framework/component Enabled state and ring eligibility.
      - ExcludeSoftPaqs remains enforced.
      - An existing Deployment.active flag is not bypassed.

    -ForceAll:
      - Does not use a Evaluation snapshot or SPList.
      - Bypasses framework/component Enabled state, ring eligibility and
        ExcludeSoftPaqs.
      - Bypasses PSADT and invokes HPIA directly for immediate full remediation.
      - Uses the fixed full AutoInstallable scope and does not use an SPList.
      - Normal and ForceRun do not bypass an existing Deployment.active ownership flag.
      - ForceAll ownership handling belongs to its dedicated direct-HPIA remediation path.

    Ownership contract:
      - DriverDeployer creates Deployment.active immediately before PSADT
        launch.
      - While the flag exists, later DriverDeployer executions perform no action.
      - PSADT keeps the flag while the deployment is active or deferred.
      - PSADT removes the flag when the deployment reaches a final result.
      - If PSADT cannot be started, DriverDeployer removes the newly created flag.

.REGISTRY
    Framework:
      HKLM\SOFTWARE\HPDriverComplianceFramework
        Enabled
        ExcludeSoftPaqs

    DriverDeployer:
      HKLM\SOFTWARE\HPDriverComplianceFramework\DriverDeployer
        Enabled
        Ring
        BroadDelayDays

.CONFIGURATION
    Configuration precedence:
      1. Built-in defaults defined in the Built-in Configuration Defaults block.
      2. Registry / enterprise policy values override matching built-in defaults.

    For standalone environments without centralized policy management, the
    built-in defaults can be customized before deployment.

.DEFAULTS
    Built-in defaults:
      FrameworkEnabled    = False
      DeployerEnabled     = False
      ExcludeSoftPaqs     = none
      Ring                = Broad
      BroadDelayDays      = 21

    These built-in defaults represent the Broad deployment policy.

    Pilot snapshots are deploy-eligible immediately. Broad snapshots become
    deploy-eligible BroadDelayDays after the successful Evaluation snapshot
    timestamp.

    Deployment executable and arguments are framework constants:
      C:\HPIA\DriverDeployment\Invoke-AppDeployToolkit.exe
      -DeploymentType Install -DeployMode Interactive

.OUTPUT
    Component log:
      C:\HPIA\IAReport\DriverDeployer-<ComputerName>.log

    Deployment handoff:
      C:\HPIA\IAReport\Deployment\Deployment.request.json
      C:\HPIA\IAReport\Deployment\Deployment.splist.txt
      C:\HPIA\IAReport\Deployment\Deployment.active

    Persistent deployment completion state:
      C:\HPIA\IAReport\Snapshots\Evaluation-<yyyy-MM-Wn>.deployed

.RETENTION
    DriverDeployer does not maintain evaluation snapshot history.

    DriverEvaluator owns evaluation snapshot retention, including the persistent
    .deployed completion marker. Deployment.active, Deployment.request.json and
    Deployment.splist.txt belong to the transient deployment handoff workflow.

.NOTES
    ComponentVersion is injected by the release workflow.
#>

[CmdletBinding()]
param(
    [switch]$ForceRun,
    [switch]$ForceAll
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$FrameworkName = "HP Driver Compliance Framework"
$ScriptName = "DriverDeployer"
$ComponentVersion = "__COMPONENT_VERSION__"

$FrameworkRegistryPath = "HKLM:\SOFTWARE\HPDriverComplianceFramework"
$ComponentRegistryPath = "$FrameworkRegistryPath\DriverDeployer"

$IAReportFolder = "C:\HPIA\IAReport"
$SnapshotFolder = Join-Path $IAReportFolder "Snapshots"
$DeploymentFolder = Join-Path $IAReportFolder "Deployment"
$LogFile = Join-Path $IAReportFolder "$ScriptName-$env:COMPUTERNAME.log"
$RequestFile = Join-Path $DeploymentFolder "Deployment.request.json"
$DeploymentSPListFile = Join-Path $DeploymentFolder "Deployment.splist.txt"
$ActiveFlagFile = Join-Path $DeploymentFolder "Deployment.active"

# ============================================================
# Built-in Configuration Defaults
# ============================================================
# Customize these values before deployment for standalone environments.
# Registry / enterprise policy values override matching defaults when present.

$DefaultFrameworkEnabled = $false
$DefaultDeployerEnabled = $false
$DefaultExcludeSoftPaqs = @()
$DefaultRing = "Broad"
$DefaultBroadDelayDays = 21
$ConnectivityProbeUri = "https://hpia.hpcloud.hp.com/"
$ConnectivityProbeTimeoutSeconds = 10
$DeploymentCommand = "C:\HPIA\DriverDeployment\Invoke-AppDeployToolkit.exe"
$DeploymentArguments = "-DeploymentType Install -DeployMode Interactive"
$HPIACommand = "C:\HPIA\HP Image Assistant\HPImageAssistant.exe"
$HPIAForceAllArguments = '/Operation:Analyze /Category:Drivers,Software,Firmware,Accessories /Selection:All /InstallType:AutoInstallable /Action:Install /AutoCleanup /Noninteractive /Debug /ReportFolder:"C:\HPIA\IAReport"'
$DriverDeploymentScript = "C:\HPIA\DriverDeployment\Invoke-AppDeployToolkit.ps1"
$PSADTDeferHistoryPath = "HKLM:\SOFTWARE\PSAppDeployToolkit\DeferHistory"


$ExecutionId = [guid]::NewGuid().ToString()
$Timer = [Diagnostics.Stopwatch]::StartNew()
$Outcome = "NoAction"
$Reason = ""
$SnapshotExecutionId = ""
$EffectiveSoftPaqCount = 0
function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("INFO","WARNING","ERROR")][string]$Level = "INFO"
    )
    if (-not (Test-Path -LiteralPath $IAReportFolder)) {
        New-Item -Path $IAReportFolder -ItemType Directory -Force | Out-Null
    }
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"),$Level,$Message
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
}

function Get-HPIABaseVersion
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [string]$VersionString
    )

    if ($VersionString -match '^(\d+)\.(\d+)\.(\d+)')
    {
        return "$($Matches[1]).$($Matches[2]).$($Matches[3])"
    }

    throw "Unable to parse HP Image Assistant version: $VersionString"
}

function Invoke-HPIAInstallOrUpdate
{
    [CmdletBinding()]
    param()

    $DownloadPath = 'C:\HPIA'
    $InstallPath = 'C:\HPIA\HP Image Assistant'
    $HPIAExe = Join-Path -Path $InstallPath -ChildPath 'HPImageAssistant.exe'
    $DownloadedSoftpaq = $null

    Write-Log -Message 'Starting HP Image Assistant version check.'

    foreach ($RequiredCommand in @(
        'Get-HPImageAssistantUpdateInfo',
        'Install-HPImageAssistant'
    ))
    {
        if (-not (Get-Command -Name $RequiredCommand -ErrorAction SilentlyContinue))
        {
            throw "Required HP CMSL command is not available: $RequiredCommand"
        }
    }

    $UpdateInfo = Get-HPImageAssistantUpdateInfo -ErrorAction Stop
    $LatestVersion = $UpdateInfo.Version.ToString()

    if ([string]::IsNullOrWhiteSpace($LatestVersion))
    {
        throw 'Get-HPImageAssistantUpdateInfo did not return a Version.'
    }

    $LatestBaseVersion = Get-HPIABaseVersion -VersionString $LatestVersion
    Write-Log -Message "Latest HP Image Assistant version: [$LatestVersion]"

    $InstallRequired = $true

    if (Test-Path -Path $HPIAExe -PathType Leaf)
    {
        $HPIAFile = Get-Item -Path $HPIAExe -ErrorAction Stop
        $InstalledVersion = $HPIAFile.VersionInfo.FileVersion

        if ([string]::IsNullOrWhiteSpace($InstalledVersion))
        {
            throw 'Unable to read installed HP Image Assistant version.'
        }

        $InstalledBaseVersion = Get-HPIABaseVersion -VersionString $InstalledVersion
        Write-Log -Message "Installed HP Image Assistant version: [$InstalledVersion]"

        if ($InstalledBaseVersion -eq $LatestBaseVersion)
        {
            Write-Log -Message 'HP Image Assistant is already up to date.'
            $InstallRequired = $false
        }
        else
        {
            Write-Log -Message "HP Image Assistant update required. Installed release: [$InstalledBaseVersion]; latest release: [$LatestBaseVersion]"
        }
    }
    else
    {
        Write-Log -Message 'HP Image Assistant is not installed.' -Level 'WARNING'
    }

    if ($InstallRequired)
    {
        if (-not (Test-Path -Path $DownloadPath -PathType Container))
        {
            New-Item -Path $DownloadPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-Log -Message "Created HP Image Assistant download folder: [$DownloadPath]"
        }

        if (-not (Test-Path -Path $InstallPath -PathType Container))
        {
            New-Item -Path $InstallPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-Log -Message "Created HP Image Assistant installation folder: [$InstallPath]"
        }

        $StaleSoftpaqs = Get-ChildItem -Path $DownloadPath -Filter 'hp-hpia-*.exe' -File -ErrorAction SilentlyContinue
        foreach ($StaleSoftpaq in $StaleSoftpaqs)
        {
            Write-Log -Message "Removing stale HP Image Assistant SoftPaq: [$($StaleSoftpaq.FullName)]"
            Remove-Item -Path $StaleSoftpaq.FullName -Force -ErrorAction Stop
        }

        Write-Log -Message "Downloading HP Image Assistant [$LatestVersion] to: [$DownloadPath]"

        $DownloadParams = @{
            DestinationPath = $DownloadPath
            ErrorAction = 'Stop'
        }

        $DownloadOutput = Install-HPImageAssistant @DownloadParams 2>&1
        foreach ($OutputLine in $DownloadOutput)
        {
            if ($null -ne $OutputLine -and -not [string]::IsNullOrWhiteSpace($OutputLine.ToString()))
            {
                Write-Log -Message "Install-HPImageAssistant: $($OutputLine.ToString())"
            }
        }

        $ExpectedSoftpaq = Join-Path -Path $DownloadPath -ChildPath "hp-hpia-$LatestVersion.exe"
        if (Test-Path -Path $ExpectedSoftpaq -PathType Leaf)
        {
            $DownloadedSoftpaq = Get-Item -Path $ExpectedSoftpaq -ErrorAction Stop
        }
        else
        {
            $DownloadedSoftpaq = Get-ChildItem -Path $DownloadPath -Filter 'hp-hpia-*.exe' -File -ErrorAction SilentlyContinue |
                Sort-Object -Property LastWriteTime -Descending |
                Select-Object -First 1
        }

        if ($null -eq $DownloadedSoftpaq)
        {
            throw "Downloaded HP Image Assistant SoftPaq was not found in: $DownloadPath"
        }

        Write-Log -Message "Downloaded HP Image Assistant SoftPaq: [$($DownloadedSoftpaq.FullName)]"

        $OldFiles = Get-ChildItem -Path $InstallPath -Force -ErrorAction SilentlyContinue
        if ($OldFiles)
        {
            Write-Log -Message "Removing old extracted HP Image Assistant files from: [$InstallPath]"
            $OldFiles | Remove-Item -Recurse -Force -ErrorAction Stop
        }

        Write-Log -Message "Extracting HP Image Assistant to: [$InstallPath]"

        $ExtractArgumentString = '/s /e /f "{0}"' -f $InstallPath
        $ExtractProcess = Start-Process `
            -FilePath $DownloadedSoftpaq.FullName `
            -ArgumentList $ExtractArgumentString `
            -Wait `
            -PassThru `
            -WindowStyle Hidden `
            -ErrorAction Stop

        Write-Log -Message "HP Image Assistant extractor exit code: [$($ExtractProcess.ExitCode)]"

        if (-not (Test-Path -Path $HPIAExe -PathType Leaf))
        {
            throw "HPImageAssistant.exe was not found after extraction: $HPIAExe"
        }

        $HPIAFile = Get-Item -Path $HPIAExe -ErrorAction Stop
        $InstalledVersion = $HPIAFile.VersionInfo.FileVersion

        if ([string]::IsNullOrWhiteSpace($InstalledVersion))
        {
            throw 'Unable to read installed HP Image Assistant version after extraction.'
        }

        $InstalledBaseVersion = Get-HPIABaseVersion -VersionString $InstalledVersion
        Write-Log -Message "Installed HP Image Assistant version after extraction: [$InstalledVersion]"

        if ($InstalledBaseVersion -ne $LatestBaseVersion)
        {
            throw "Installed version [$InstalledVersion] does not match expected release [$LatestVersion]."
        }

        if (Test-Path -Path $DownloadedSoftpaq.FullName -PathType Leaf)
        {
            Write-Log -Message "Removing downloaded HP Image Assistant SoftPaq: [$($DownloadedSoftpaq.FullName)]"
            Remove-Item -Path $DownloadedSoftpaq.FullName -Force -ErrorAction Stop
        }

        Write-Log -Message 'HP Image Assistant successfully installed/updated.'
    }

    Write-Log -Message "HP Image Assistant executable path: [$HPIAExe]"
}

function Get-RegObject([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        return Get-ItemProperty -LiteralPath $Path -ErrorAction Stop
    }
    return $null
}

function Get-Enabled($Object,[string]$Scope,[bool]$DefaultValue) {
    if ($null -eq $Object) { return $DefaultValue }

    $Property = $Object.PSObject.Properties["Enabled"]
    if ($null -eq $Property) { return $DefaultValue }

    $v = [int]$Property.Value
    if ($v -notin @(0,1)) { throw "$Scope Enabled must be REG_DWORD 0 or 1." }
    return ($v -eq 1)
}

function Get-OptionalRegistryValue {
    param(
        $Object,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $Property = $Object.PSObject.Properties[$Name]
    if ($null -eq $Property) {
        return $null
    }

    return $Property.Value
}

function Get-Exclusions($FrameworkRegistry) {
    if ($null -eq $FrameworkRegistry) {
        return @($DefaultExcludeSoftPaqs)
    }

    $RawExclusions = Get-OptionalRegistryValue -Object $FrameworkRegistry -Name "ExcludeSoftPaqs"

    if ($null -eq $RawExclusions -or
        [string]::IsNullOrWhiteSpace([string]$RawExclusions)) {
        return @($DefaultExcludeSoftPaqs)
    }

    return @(
        ([string]$RawExclusions) -split ',' |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ } |
        ForEach-Object {
            $sp = $_ -replace '^(?i)sp',''
            if ($sp -notmatch '^\d+$') { throw "Invalid ExcludeSoftPaqs entry [$_]." }
            $sp
        } | Select-Object -Unique
    )
}

function Get-LatestSnapshot {
    $markers = @(
        Get-ChildItem -LiteralPath $SnapshotFolder -Filter "Evaluation-*.success" `
            -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    )

    foreach ($marker in $markers) {
        $base = $marker.Name -replace '\.success$',''
        $manifestPath = Join-Path $SnapshotFolder "$base.manifest.json"
        $spListPath = Join-Path $SnapshotFolder "$base.splist.txt"
        if (-not (Test-Path $manifestPath) -or -not (Test-Path $spListPath)) { continue }

        try {
            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
            if ([string]::IsNullOrWhiteSpace([string]$manifest.ExecutionId)) { continue }

            $markerMap = @{}
            foreach ($line in Get-Content $marker.FullName) {
                if ($line -match '^(?<k>[^=]+)=(?<v>.*)$') { $markerMap[$Matches.k]=$Matches.v }
            }
            if ($markerMap.ContainsKey("ExecutionId") -and
                $markerMap["ExecutionId"] -ne [string]$manifest.ExecutionId) { continue }

            $spList = @(Get-Content $spListPath | ForEach-Object {$_.Trim()} | Where-Object {$_ -match '^\d+$'})
            $manifestSP = @($manifest.SoftPaqs | ForEach-Object {[string]$_})
            if (($spList -join ',') -ne ($manifestSP -join ',')) { continue }

            return [pscustomobject]@{
                Manifest=$manifest
                ManifestPath=$manifestPath
                SPListPath=$spListPath
                SoftPaqs=$spList
            }
        } catch { continue }
    }
    return $null
}

function Write-Request([string]$Mode,[string]$SnapshotId,[string]$SPListPath) {
    if (-not (Test-Path -LiteralPath $DeploymentFolder -PathType Container)) {
        New-Item -Path $DeploymentFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    $request = [ordered]@{
        CreatedAt=(Get-Date).ToString("o")
        ExecutionId=$ExecutionId
        ComponentVersion=$ComponentVersion
        Mode=$Mode
        SnapshotExecutionId=$SnapshotId
        SPListPath=$SPListPath
    }
    $tmp="$RequestFile.tmp"
    $request | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item $tmp $RequestFile -Force
}


function Set-ActiveFlag([string]$Mode,[string]$SnapshotId) {
    if (-not (Test-Path -LiteralPath $DeploymentFolder -PathType Container)) {
        New-Item -Path $DeploymentFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    if (Test-Path -LiteralPath $ActiveFlagFile) {
        throw "Deployment ownership flag already exists: $ActiveFlagFile"
    }

    $flag = @(
        "ExecutionId=$ExecutionId"
        "SnapshotExecutionId=$SnapshotId"
        "Mode=$Mode"
        "CreatedAt=$((Get-Date).ToString('o'))"
    )

    $temp = "$ActiveFlagFile.tmp"
    $flag | Set-Content -LiteralPath $temp -Encoding UTF8

    try {
        Move-Item -LiteralPath $temp -Destination $ActiveFlagFile -ErrorAction Stop
    }
    catch {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        throw
    }

    Write-Log "Deployment ownership flag created: [$ActiveFlagFile]"
}

function Remove-ActiveFlagAfterLaunchFailure {
    if (Test-Path -LiteralPath $ActiveFlagFile) {
        Remove-Item -LiteralPath $ActiveFlagFile -Force -ErrorAction SilentlyContinue
        Write-Log "Deployment ownership flag removed because PSADT could not be started." "WARNING"
    }
}

function Start-Deployment([string]$Command,[string]$Arguments) {
    if (-not (Test-Path -LiteralPath $Command -PathType Leaf)) {
        throw "Deployment command not found: $Command"
    }

    Write-Log "Starting PSADT deployment: [$Command] [$Arguments]"
    Start-Process -FilePath $Command -ArgumentList $Arguments -ErrorAction Stop | Out-Null
    Write-Log "PSADT process started successfully."
}

function Get-DriverDeploymentMetadata {
    if (-not (Test-Path -LiteralPath $DriverDeploymentScript -PathType Leaf)) {
        throw "DriverDeployment PSADT script was not found: $DriverDeploymentScript"
    }

    $content = Get-Content -LiteralPath $DriverDeploymentScript -Raw -ErrorAction Stop
    $metadata = [ordered]@{}

    foreach ($name in @("AppVendor","AppName","AppVersion","AppArch","AppLang","AppRevision")) {
        $pattern = "(?m)^\s*" + [regex]::Escape($name) + "\s*=\s*(['""])(.*?)\1\s*$"
        $matches = [regex]::Matches($content, $pattern)

        if ($matches.Count -ne 1) {
            throw "Unable to resolve DriverDeployment metadata [$name] uniquely from: $DriverDeploymentScript"
        }

        $metadata[$name] = $matches[0].Groups[2].Value
    }

    return [pscustomobject]$metadata
}


function Get-DriverDeploymentInstallName {
    param(
        [Parameter(Mandatory)]
        [psobject]$Metadata
    )

    $parts = @(
        [string]$Metadata.AppVendor
        [string]$Metadata.AppName
        [string]$Metadata.AppVersion
        [string]$Metadata.AppArch
        [string]$Metadata.AppLang
        [string]$Metadata.AppRevision
    )

    $normalized = @(
        $parts |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { ($_ -replace '\s', '') }
    )

    if ($normalized.Count -eq 0) {
        throw "Unable to generate DriverDeployment PSADT InstallName from metadata."
    }

    return ($normalized -join "_")
}


function Test-SnapshotDeployed {
    param(
        [Parameter(Mandatory)]
        [string]$SnapshotExecutionId
    )

    if ([string]::IsNullOrWhiteSpace($SnapshotExecutionId)) {
        return $false
    }

    foreach ($manifestFile in @(
        Get-ChildItem `
            -LiteralPath $SnapshotFolder `
            -Filter "Evaluation-*.manifest.json" `
            -File `
            -ErrorAction SilentlyContinue
    )) {
        try {
            $manifest =
                Get-Content -LiteralPath $manifestFile.FullName -Raw -ErrorAction Stop |
                ConvertFrom-Json -ErrorAction Stop

            if ([string]$manifest.ExecutionId -ne $SnapshotExecutionId) {
                continue
            }

            $deployedMarkerPath =
                $manifestFile.FullName -replace '\.manifest\.json$', '.deployed'

            if (-not (Test-Path -LiteralPath $deployedMarkerPath -PathType Leaf)) {
                return $false
            }

            $deployedMarker = @{}

            foreach ($line in Get-Content -LiteralPath $deployedMarkerPath -ErrorAction Stop) {
                if ($line -match '^(?<k>[^=]+)=(?<v>.*)$') {
                    $deployedMarker[$Matches.k] = $Matches.v
                }
            }

            return (
                $deployedMarker.ContainsKey("SnapshotExecutionId") -and
                $deployedMarker["SnapshotExecutionId"] -eq $SnapshotExecutionId
            )
        }
        catch {
            Write-Log "Unable to validate deployed state for snapshot [$SnapshotExecutionId]: $($_.Exception.Message)" "WARNING"
            return $false
        }
    }

    return $false
}


function Get-DriverDeploymentDeferState {
    $metadata = Get-DriverDeploymentMetadata
    $installName = Get-DriverDeploymentInstallName -Metadata $metadata
    $deferKey = Join-Path -Path $PSADTDeferHistoryPath -ChildPath $installName
    $present = Test-Path -LiteralPath $deferKey -PathType Container
    $timesRemaining = $null

    if ($present) {
        $deferObject = Get-ItemProperty -LiteralPath $deferKey -ErrorAction Stop
        $property = $deferObject.PSObject.Properties["DeferTimesRemaining"]

        if ($null -ne $property) {
            $timesRemaining = $property.Value
        }
    }

    return [pscustomobject]@{
        InstallName = $installName
        RegistryPath = $deferKey
        Present = $present
        DeferTimesRemaining = $timesRemaining
    }
}


function Test-HPConnectivity {
    try {
        Write-Log "Checking HP connectivity: [$ConnectivityProbeUri]"
        $response = Invoke-WebRequest `
            -Uri $ConnectivityProbeUri `
            -Method Head `
            -TimeoutSec $ConnectivityProbeTimeoutSeconds `
            -UseBasicParsing `
            -ErrorAction Stop
        Write-Log "HP connectivity check succeeded. HTTP status: [$($response.StatusCode)]"
        return $true
    }
    catch {
        Write-Log "HP connectivity check failed: [$($_.Exception.Message)]" "WARNING"
        return $false
    }
}


function Test-PSADTBusy {
    try {
        $processes = @(
            Get-CimInstance -ClassName Win32_Process -ErrorAction Stop |
                Where-Object {
                    $_.Name -ieq "Invoke-AppDeployToolkit.exe" -or
                    (
                        $_.Name -in @("powershell.exe","pwsh.exe") -and
                        -not [string]::IsNullOrWhiteSpace([string]$_.CommandLine) -and
                        $_.CommandLine -match 'Invoke-AppDeployToolkit\.ps1'
                    )
                }
        )
    }
    catch {
        throw "Unable to determine global PSADT process state: $($_.Exception.Message)"
    }

    if ($processes.Count -gt 0) {
        foreach ($process in $processes) {
            Write-Log "Active PSADT process detected. PID=[$($process.ProcessId)] Name=[$($process.Name)]" "WARNING"
        }
        return $true
    }

    return $false
}


function Get-DriverDeploymentNamespacePrefix {
    $metadata = Get-DriverDeploymentMetadata
    $vendor = ([string]$metadata.AppVendor -replace '\s','')
    $name = ([string]$metadata.AppName -replace '\s','')

    if ([string]::IsNullOrWhiteSpace($vendor) -or [string]::IsNullOrWhiteSpace($name)) {
        throw "Unable to generate DriverDeployment PSADT namespace prefix from metadata."
    }

    return "${vendor}_${name}_"
}


function Clear-ForceAllPendingState {
    Write-Log "ForceAll succeeded. Clearing previous HP-DCF evaluation and deployment state."

    $snapshotPatterns = @(
        "Evaluation-*.manifest.json",
        "Evaluation-*.splist.txt",
        "Evaluation-*.success",
        "Evaluation-*.failed",
        "Evaluation-*.deployed"
    )

    foreach ($pattern in $snapshotPatterns) {
        foreach ($file in @(Get-ChildItem -LiteralPath $SnapshotFolder -Filter $pattern -File -ErrorAction SilentlyContinue)) {
            Write-Log "Removing obsolete evaluation snapshot artifact: [$($file.FullName)]"
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
        }
    }

    foreach ($file in @($RequestFile,$DeploymentSPListFile,$ActiveFlagFile)) {
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            Write-Log "Removing obsolete deployment state: [$file]"
            Remove-Item -LiteralPath $file -Force -ErrorAction Stop
        }
    }

    $prefix = Get-DriverDeploymentNamespacePrefix
    Write-Log "DriverDeployment PSADT defer namespace prefix: [$prefix]"

    if (Test-Path -LiteralPath $PSADTDeferHistoryPath -PathType Container) {
        foreach ($key in @(Get-ChildItem -LiteralPath $PSADTDeferHistoryPath -ErrorAction Stop)) {
            if ($key.PSChildName.StartsWith($prefix,[System.StringComparison]::OrdinalIgnoreCase)) {
                Write-Log "Removing HP-DCF DriverDeployment PSADT defer state: [$($key.PSPath)]"
                Remove-Item -LiteralPath $key.PSPath -Recurse -Force -ErrorAction Stop
            }
        }
    }

    Write-Log "ForceAll pending-state cleanup completed successfully."
}


function Start-ForceAllHPIARemediation {
    Invoke-HPIAInstallOrUpdate

    if (-not (Test-Path -LiteralPath $HPIACommand -PathType Leaf)) {
        throw "HP Image Assistant was not found: $HPIACommand"
    }

    $HPIAVersion = (
        Get-Item -LiteralPath $HPIACommand -ErrorAction Stop
    ).VersionInfo.FileVersion

    if ([string]::IsNullOrWhiteSpace($HPIAVersion)) {
        $HPIAVersion = "Unknown"
    }

    Write-Log "ForceAll HP Image Assistant version: [$HPIAVersion]"
    Write-Log "ForceAll direct HPIA remediation starting."
    Write-Log "HPIA executable: [$HPIACommand]"
    Write-Log "HPIA arguments: [$HPIAForceAllArguments]"
    Write-Log "PSADT is bypassed for ForceAll."

    $process = Start-Process `
        -FilePath $HPIACommand `
        -ArgumentList $HPIAForceAllArguments `
        -Wait `
        -PassThru `
        -ErrorAction Stop

    $exitCode = [int]$process.ExitCode
    Write-Log "ForceAll HPIA process finished with exit code [$exitCode]."

    switch ($exitCode) {
        0 { Write-Log "ForceAll HPIA remediation completed successfully." }
        256 { Write-Log "ForceAll HPIA remediation completed with no applicable recommendations." }
        1641 { Write-Log "ForceAll HPIA remediation completed successfully and initiated a restart." "WARNING" }
        3010 { Write-Log "ForceAll HPIA remediation completed successfully and a restart is required." "WARNING" }
        3020 { throw "ForceAll HPIA remediation failed: one or more SoftPaq installations failed. Exit code [3020]." }
        4098 { throw "ForceAll HPIA remediation failed: no internet connection. Exit code [4098]." }
        4099 { throw "ForceAll HPIA remediation failed: invalid SoftPaq number. Exit code [4099]." }
        default { throw "ForceAll HPIA remediation failed with exit code [$exitCode]." }
    }

    return $exitCode
}


try {
    if ($ForceRun -and $ForceAll) { throw "-ForceRun and -ForceAll cannot be combined." }

    $fw = Get-RegObject $FrameworkRegistryPath
    $cfg = Get-RegObject $ComponentRegistryPath
    $fwEnabled = Get-Enabled $fw "Framework" $DefaultFrameworkEnabled
    $deployerEnabled = Get-Enabled $cfg "DriverDeployer" $DefaultDeployerEnabled

    $ring=$DefaultRing
    $broadDelay=$DefaultBroadDelayDays
    $command=$DeploymentCommand
    $arguments=$DeploymentArguments

    if ($null -ne $cfg) {
        $RegistryRing = Get-OptionalRegistryValue -Object $cfg -Name "Ring"
        $RegistryBroadDelayDays = Get-OptionalRegistryValue -Object $cfg -Name "BroadDelayDays"
        if ($null -ne $RegistryRing -and -not [string]::IsNullOrWhiteSpace([string]$RegistryRing)) {
            $ring=[string]$RegistryRing
        }
        if ($null -ne $RegistryBroadDelayDays) {
            $broadDelay=[int]$RegistryBroadDelayDays
        }
    }

    if ($ring -notin @("Pilot","Broad")) { throw "Ring must be Pilot or Broad." }
    if ($broadDelay -lt 0 -or $broadDelay -gt 365) { throw "BroadDelayDays must be 0..365." }

    $mode = if ($ForceAll) {"ForceAll"} elseif ($ForceRun) {"ForceRun"} else {"Normal"}
    Write-Log "$FrameworkName / $ScriptName started."
    Write-Log "Component version: [$ComponentVersion]"
    Write-Log "Execution ID: [$ExecutionId]"
    Write-Log "Execution mode: [$mode]"
    Write-Log "Framework enabled: [$fwEnabled]"
    Write-Log "DriverDeployer enabled: [$deployerEnabled]"
    Write-Log "Ring: [$ring]"
    if ($ring -eq "Pilot") {
        Write-Log "Deployment delay: [None - Pilot deployments are immediately eligible.]"
    }
    else {
        Write-Log "Broad deployment delay: [$broadDelay] day(s)."
    }

    $deferState = $null
    if (-not $ForceAll) {
        $deferState = Get-DriverDeploymentDeferState
        Write-Log "DriverDeployment InstallName: [$($deferState.InstallName)]"
        Write-Log "DriverDeployment defer state: [$($deferState.Present)]"

        if ($deferState.Present) {
            Write-Log "DriverDeployment DeferTimesRemaining: [$($deferState.DeferTimesRemaining)]"
        }
    }

    if (-not $ForceRun -and -not $ForceAll) {
        if (-not $fwEnabled) { $Reason="FrameworkDisabled"; Write-Log "Framework disabled. No action."; return }
        if (-not $deployerEnabled) { $Reason="DriverDeployerDisabled"; Write-Log "DriverDeployer disabled. No action."; return }
    }

    if ((-not $ForceAll) -and $null -ne $deferState -and $deferState.Present) {
        Write-Log "Deferred DriverDeployment detected."

        $deferredSnapshotExecutionId = ""

        if (Test-Path -LiteralPath $RequestFile -PathType Leaf) {
            try {
                $deferredRequest =
                    Get-Content -LiteralPath $RequestFile -Raw -ErrorAction Stop |
                    ConvertFrom-Json -ErrorAction Stop

                $deferredSnapshotExecutionId =
                    [string]$deferredRequest.SnapshotExecutionId
            }
            catch {
                Write-Log "Unable to read deferred deployment request: $($_.Exception.Message)" "WARNING"
            }
        }

        if (
            -not [string]::IsNullOrWhiteSpace($deferredSnapshotExecutionId) -and
            (Test-SnapshotDeployed -SnapshotExecutionId $deferredSnapshotExecutionId)
        ) {
            $SnapshotExecutionId = $deferredSnapshotExecutionId

            Write-Log "Deferred DriverDeployment belongs to a snapshot that has already been deployed successfully. Clearing stale deferred state."

            if (Test-Path -LiteralPath $deferState.RegistryPath -PathType Container) {
                Write-Log "Removing stale DriverDeployment PSADT defer state: [$($deferState.RegistryPath)]"
                Remove-Item `
                    -LiteralPath $deferState.RegistryPath `
                    -Recurse `
                    -Force `
                    -ErrorAction Stop
            }

            foreach ($file in @($RequestFile,$DeploymentSPListFile,$ActiveFlagFile)) {
                if (Test-Path -LiteralPath $file -PathType Leaf) {
                    Write-Log "Removing stale deployment handoff state: [$file]"
                    Remove-Item `
                        -LiteralPath $file `
                        -Force `
                        -ErrorAction Stop
                }
            }

            $Reason = "AlreadyDeployed"
            Write-Log "Stale deferred deployment state cleared. No action."
            return
        }

        Write-Log "Deferred deployment resume takes precedence over snapshot selection."

        if (Test-PSADTBusy) {
            $Reason = "PSADTBusy"
            Write-Log "Another PSADT deployment is active. Deferred DriverDeployment will be retried on a later execution. No action."
            return
        }

        Write-Log "No active PSADT deployment detected. Resuming deferred DriverDeployment."
        Start-Deployment $command $arguments
        $Outcome = "Started"
        $Reason = "DeferredResume"
        return
    }

    if ((-not $ForceAll) -and (Test-Path -LiteralPath $ActiveFlagFile -PathType Leaf)) {
        $Reason="DeploymentActive"
        Write-Log "Deployment ownership flag exists without current DriverDeployment defer state: [$ActiveFlagFile]. No action."
        return
    }

    if ($ForceAll) {
        $forceAllExitCode = Start-ForceAllHPIARemediation
        $Outcome = "Success"
        $Reason = if ($forceAllExitCode -in @(1641,3010)) {"ForceAllRestartRequired"} elseif ($forceAllExitCode -eq 256) {"ForceAllNoRecommendations"} else {"ForceAll"}
        Clear-ForceAllPendingState
        return
    }

    $snapshot=Get-LatestSnapshot
    if ($null -eq $snapshot) { $Reason="NoValidSnapshot"; Write-Log "No valid complete Evaluation snapshot found."; return }

    $SnapshotExecutionId=[string]$snapshot.Manifest.ExecutionId
    Write-Log "Selected snapshot execution ID: [$SnapshotExecutionId]"
    Write-Log "Selected manifest: [$($snapshot.ManifestPath)]"
    Write-Log "Selected SPList: [$($snapshot.SPListPath)]"

    if (-not $ForceRun -and (Test-SnapshotDeployed -SnapshotExecutionId $SnapshotExecutionId)) {
        $Reason = "AlreadyDeployed"
        Write-Log "Selected snapshot has already been deployed successfully. No action."
        return
    }

    if ([int]$snapshot.Manifest.RecommendationCount -eq 0) {
        $Reason="NoRecommendations"
        Write-Log "Selected snapshot contains no recommendations. No action."
        return
    }

    $detectedAt=[datetimeoffset]::Parse([string]$snapshot.Manifest.Timestamp)
    $delay=if ($ring -eq "Pilot") {0} else {$broadDelay}
    $eligibleAt=$detectedAt.AddDays($delay)
    Write-Log "Ring eligible at: [$($eligibleAt.ToString('o'))]"

    if (-not $ForceRun -and [datetimeoffset]::Now -lt $eligibleAt) {
        $Reason="RingNotEligible"; Write-Log "Ring is not yet eligible. No action."; return
    }


    $exclusions=Get-Exclusions $fw
    Write-Log "Framework ExcludeSoftPaqs: [$($exclusions -join ',')]"
    $effective=@($snapshot.SoftPaqs | Where-Object {$_ -notin $exclusions})
    $EffectiveSoftPaqCount=$effective.Count
    Write-Log "Snapshot SoftPaq count: [$($snapshot.SoftPaqs.Count)]"
    Write-Log "Effective deployment SoftPaq count: [$EffectiveSoftPaqCount]"

    if ($EffectiveSoftPaqCount -eq 0) {
        $Reason="NoApplicableSoftPaqs"; Write-Log "No deployable SoftPaq remains. No action."; return
    }

    if (Test-PSADTBusy) {
        $Reason = "PSADTBusy"
        Write-Log "Another PSADT deployment is active. Deployment handoff was not created and will be retried on a later execution. No action."
        return
    }

    if (-not (Test-HPConnectivity)) {
        $Reason = "NoInternetConnection"
        Write-Log "HP connectivity is unavailable. Deployment handoff was not created and will be retried on a later execution. No action."
        return
    }

    if (-not (Test-Path -LiteralPath $DeploymentFolder -PathType Container)) {
        New-Item -Path $DeploymentFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
        Write-Log "Created deployment handoff folder: [$DeploymentFolder]"
    }

    $effective | Set-Content -LiteralPath $DeploymentSPListFile -Encoding ASCII
    $requestMode=if ($ForceRun) {"ForceRun"} else {"Snapshot"}
    Write-Request $requestMode $SnapshotExecutionId $DeploymentSPListFile

    Write-Log "Deployment request prepared."
    Write-Log "Deployment SPList: [$DeploymentSPListFile]"
    Write-Log "SoftPaqs represented by deployment SPList: [$($effective -join ',')]"

    Set-ActiveFlag $requestMode $SnapshotExecutionId
    try {
        Start-Deployment $command $arguments
    }
    catch {
        Remove-ActiveFlagAfterLaunchFailure
        throw
    }

    $Outcome="Started"; $Reason=if ($ForceRun) {"ForceRun"} else {"Eligible"}
}
catch {
    $Outcome="Failed"
    $Reason=$_.Exception.Message
    Write-Log $_.Exception.Message "ERROR"
}
finally {
    if ($Timer.IsRunning) {$Timer.Stop()}
    $duration=[math]::Round($Timer.Elapsed.TotalSeconds,2)
    $mode=if ($ForceAll) {"ForceAll"} elseif ($ForceRun) {"ForceRun"} else {"Normal"}
    Write-Log "SUMMARY|ExecutionId=$ExecutionId|ComponentVersion=$ComponentVersion|Mode=$mode|Outcome=$Outcome|Reason=$Reason|SnapshotExecutionId=$SnapshotExecutionId|SoftPaqs=$EffectiveSoftPaqCount|DurationSeconds=$duration"
    if ($Outcome -eq "Failed") {exit 1}
    exit 0
}
