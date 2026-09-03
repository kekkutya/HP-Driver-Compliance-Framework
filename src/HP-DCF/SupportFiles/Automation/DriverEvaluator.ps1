<#
.SYNOPSIS
    HP Driver Compliance Framework - DriverEvaluator

.DESCRIPTION
    Evaluates the device with HP Image Assistant (HPIA) and creates a validated
    point-in-time snapshot of applicable AutoInstallable SoftPaq recommendations.

    DriverEvaluator never downloads or installs SoftPaq binaries. Download and
    installation are exclusively handled by the deployment PSADT / HPIA workflow.

    HPIA evaluation scope is fixed:
      /Operation:Analyze
      /Category:Drivers,Software,Firmware,Accessories
      /Selection:All
      /InstallType:AutoInstallable
      /Action:List
      /Noninteractive
      /Debug

.EXECUTION
    Normal:
      - Requires framework Enabled=1.
      - Evaluates the configured schedule.
      - Supports one or more weekday occurrences in a month through WeeksOfMonth.
      - Skips an occurrence that already has a success marker.
      - Runs HPIA Analyze / List when eligible.
      - Applies the current framework ExcludeSoftPaqs list before committing
        the effective snapshot.

    -ForceRun:
      - Bypasses a missing framework Enabled value or Enabled=0.
      - Bypasses schedule eligibility.
      - Bypasses an existing current-occurrence success marker.
      - ExcludeSoftPaqs remains enforced.

.REGISTRY
    Framework:
      HKLM\SOFTWARE\HPDriverComplianceFramework
        Enabled
        ExcludeSoftPaqs

    DriverEvaluator:
      HKLM\SOFTWARE\HPDriverComplianceFramework\DriverEvaluator
        ScheduleMode
        MonthMode
        SpecificMonths
        WeeksOfMonth
        WeekParity
        DayOfWeek
        RunOnOrAfter

    WeeksOfMonth accepts comma-separated monthly weekday occurrences:
      1,2,3,4,5
      -1 = last occurrence

    Example Pilot override:
      WeeksOfMonth = 1,3
      DayOfWeek    = Wednesday
      RunOnOrAfter = True

    With RunOnOrAfter=True, a missed occurrence can be caught up later. If a
    later configured occurrence has already been reached, the newer occurrence
    supersedes an older missed occurrence.

    With RunOnOrAfter=False, evaluation is eligible only on the exact configured
    occurrence date.

.CONFIGURATION
    Configuration precedence:
      1. Built-in defaults defined in the Built-in Configuration Defaults block.
      2. Registry / enterprise policy values override matching built-in defaults.

    For standalone environments without centralized policy management, the
    built-in defaults can be customized before deployment.

.DEFAULTS
    Built-in defaults:
      FrameworkEnabled    = False
      ExcludeSoftPaqs     = none
      ScheduleMode        = Monthly
      MonthMode           = All
      SpecificMonths      = none
      WeeksOfMonth        = 3
      WeekParity          = All
      DayOfWeek           = Wednesday
      RunOnOrAfter        = False
      SnapshotRetention   = 6

    These built-in schedule defaults represent the Broad evaluation policy:
      third Wednesday of every month, with no catch-up after the scheduled day.

.OUTPUT
    Component log:
      C:\HPIA\IAReport\DriverEvaluator-<ComputerName>.log

    Evaluation snapshots:
      C:\HPIA\IAReport\Snapshots\Evaluation-<yyyy-MM-Wn>.success
      C:\HPIA\IAReport\Snapshots\Evaluation-<yyyy-MM-Wn>.failed
      C:\HPIA\IAReport\Snapshots\Evaluation-<yyyy-MM-Wn>.splist.txt
      C:\HPIA\IAReport\Snapshots\Evaluation-<yyyy-MM-Wn>.manifest.json
      C:\HPIA\IAReport\Snapshots\Evaluation-<yyyy-MM-Wn>.deployed

    Occurrence suffix examples:
      W1 = first weekday occurrence
      W3 = third weekday occurrence
      WL = last weekday occurrence

.RETENTION
    Evaluation snapshots are stored separately under C:\HPIA\IAReport\Snapshots.

    The latest 6 snapshot artifact groups are retained by default. Retention
    treats each occurrence as one artifact group and removes the expired
    .manifest.json, .splist.txt, .success, .failed and .deployed files together.

.NOTES
    ComponentVersion is injected by the release workflow.
#>


[CmdletBinding()]
param
(
    [switch]$ForceRun
)


# ============================================================
# Configuration
# ============================================================

$FrameworkName = "HP Driver Compliance Framework"
$ScriptName = "DriverEvaluator"
$ComponentVersion = "__COMPONENT_VERSION__"

$HPIAExe = "C:\HPIA\HP Image Assistant\HPImageAssistant.exe"
$ReportFolder = "C:\HPIA\IAReport"
$SnapshotFolder = Join-Path $ReportFolder "Snapshots"

$HPIATimeoutMinutes = 90
# ============================================================
# Built-in Configuration Defaults
# ============================================================
# Customize these values before deployment for standalone environments.
# Registry / enterprise policy values override matching defaults when present.

$DefaultFrameworkEnabled = $false
$DefaultExcludeSoftPaqs = @()
$DefaultSnapshotRetentionCount = 6

$DefaultScheduleConfig = @{
    ScheduleMode   = "Monthly"
    MonthMode      = "All"
    SpecificMonths = @()
    WeeksOfMonth   = @(3)
    WeekParity     = "All"
    DayOfWeek      = "Wednesday"
    RunOnOrAfter   = $false
}

$SnapshotRetentionCount = $DefaultSnapshotRetentionCount

$AcceptedHPIAExitCodes = @(0, 256, 257)


# ============================================================
# HPIA Lifecycle
# ============================================================

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
    $EvaluatorHPIAExe = Join-Path -Path $InstallPath -ChildPath 'HPImageAssistant.exe'
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

    if (Test-Path -Path $EvaluatorHPIAExe -PathType Leaf)
    {
        $HPIAFile = Get-Item -Path $EvaluatorHPIAExe -ErrorAction Stop
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

        if (-not (Test-Path -Path $EvaluatorHPIAExe -PathType Leaf))
        {
            throw "HPImageAssistant.exe was not found after extraction: $EvaluatorHPIAExe"
        }

        $HPIAFile = Get-Item -Path $EvaluatorHPIAExe -ErrorAction Stop
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

    Write-Log -Message "HP Image Assistant executable path: [$EvaluatorHPIAExe]"
}

$FrameworkRegistryPath =
    "HKLM:\SOFTWARE\HPDriverComplianceFramework"

$ComponentRegistryPath =
    "$FrameworkRegistryPath\DriverEvaluator"

$MutexName =
    "Global\HPDriverComplianceFramework-DriverEvaluator"


# ============================================================
# Help
# ============================================================

function Show-DriverEvaluatorHelp
{
    param([string]$ErrorMessage)

    if (-not [string]::IsNullOrWhiteSpace($ErrorMessage))
    {
        Write-Host ""
        Write-Host "ERROR: $ErrorMessage" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host $FrameworkName
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  DriverEvaluator.ps1 [-ForceRun]"
    Write-Host ""
    Write-Host "DriverEvaluator always runs HPIA Analyze / List."
    Write-Host "SoftPaq download and installation are handled by the deployment PSADT."
    Write-Host ""
}


# ============================================================
# Effective Schedule Configuration
# ============================================================

$ScheduleConfig = @{
    ScheduleMode   = $DefaultScheduleConfig.ScheduleMode
    MonthMode      = $DefaultScheduleConfig.MonthMode
    SpecificMonths = @($DefaultScheduleConfig.SpecificMonths)
    WeeksOfMonth   = @($DefaultScheduleConfig.WeeksOfMonth)
    WeekParity     = $DefaultScheduleConfig.WeekParity
    DayOfWeek      = $DefaultScheduleConfig.DayOfWeek
    RunOnOrAfter   = $DefaultScheduleConfig.RunOnOrAfter
}


# ============================================================
# Read Registry Configuration
# ============================================================

$FrameworkRegistry = $null
$ComponentRegistry = $null


if (Test-Path -Path $FrameworkRegistryPath -PathType Container)
{
    try
    {
        $FrameworkRegistry = Get-ItemProperty `
            -Path $FrameworkRegistryPath `
            -ErrorAction Stop
    }
    catch
    {
        Write-Host ""
        Write-Host "ERROR: Unable to read framework registry configuration." `
            -ForegroundColor Red

        Write-Host $_.Exception.Message

        exit 1
    }
}


if (Test-Path -Path $ComponentRegistryPath -PathType Container)
{
    try
    {
        $ComponentRegistry = Get-ItemProperty `
            -Path $ComponentRegistryPath `
            -ErrorAction Stop
    }
    catch
    {
        Write-Host ""
        Write-Host "ERROR: Unable to read DriverEvaluator registry configuration." `
            -ForegroundColor Red

        Write-Host $_.Exception.Message

        exit 1
    }
}


# ============================================================
# Framework Enabled
# ============================================================
#
# Missing Enabled = disabled.
#
# Enabled = 0:
#   Normal execution stops with exit 0.
#
# Enabled = 1:
#   Normal execution is allowed and continues with Mode / schedule checks.
#
# Missing Enabled or Enabled = 0 + ForceRun:
#   Disabled state is overridden for troubleshooting.
#
# ============================================================

$FrameworkEnabled = $DefaultFrameworkEnabled
$FrameworkEnabledSource = "BuiltInDefault"


if (
    $null -ne $FrameworkRegistry -and
    $null -ne $FrameworkRegistry.Enabled
)
{
    try
    {
        $RawFrameworkEnabled =
            [int]$FrameworkRegistry.Enabled

        if ($RawFrameworkEnabled -notin @(0, 1))
        {
            throw "Enabled must be REG_DWORD 0 or 1."
        }

        $FrameworkEnabled =
            ($RawFrameworkEnabled -eq 1)

        $FrameworkEnabledSource =
            "Registry"
    }
    catch
    {
        Write-Host ""
        Write-Host "ERROR: Invalid framework Enabled registry value. Expected REG_DWORD 0 or 1." `
            -ForegroundColor Red

        if (-not [string]::IsNullOrWhiteSpace($_.Exception.Message))
        {
            Write-Host $_.Exception.Message
        }

        exit 1
    }
}


if (
    -not $FrameworkEnabled -and
    -not $ForceRun
)
{
    #
    # Logging may not yet be initialized, therefore this is intentionally
    # a silent successful no-op for normal execution.
    #

    exit 0
}


# ============================================================
# Framework SoftPaq Exclusions
# ============================================================

$ConfiguredExcludeSoftPaqs = @($DefaultExcludeSoftPaqs)

if (
    $null -ne $FrameworkRegistry -and
    $null -ne $FrameworkRegistry.ExcludeSoftPaqs -and
    -not [string]::IsNullOrWhiteSpace([string]$FrameworkRegistry.ExcludeSoftPaqs)
)
{
    try
    {
        $ConfiguredExcludeSoftPaqs = @(
            ([string]$FrameworkRegistry.ExcludeSoftPaqs) -split ',' |
                ForEach-Object { $_.Trim() } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                ForEach-Object {
                    $NormalizedSoftPaq = $_ -replace '^(?i)sp', ''

                    if ($NormalizedSoftPaq -notmatch '^\d+$')
                    {
                        throw "Invalid ExcludeSoftPaqs entry [$_]. Use comma-separated SoftPaq numbers, e.g. 123456,234567."
                    }

                    $NormalizedSoftPaq
                } |
                Select-Object -Unique
        )
    }
    catch
    {
        Write-Host ""
        Write-Host "ERROR: Invalid framework ExcludeSoftPaqs registry value." -ForegroundColor Red
        Write-Host $_.Exception.Message
        exit 1
    }
}


# ============================================================
# Fixed Evaluation Configuration
# ============================================================

$ArtifactPrefix = "Evaluation"
$HPIAAction = "List"
$ExpectedHPIAOperation = "Analyze Action List"


# ============================================================
# Registry Schedule Overrides
# ============================================================

$ScheduleRegistryOverrideUsed = $false


if ($null -ne $ComponentRegistry)
{
    try
    {
        if ($null -ne $ComponentRegistry.ScheduleMode)
        {
            $ScheduleConfig.ScheduleMode =
                [string]$ComponentRegistry.ScheduleMode

            $ScheduleRegistryOverrideUsed = $true
        }


        if ($null -ne $ComponentRegistry.MonthMode)
        {
            $ScheduleConfig.MonthMode =
                [string]$ComponentRegistry.MonthMode

            $ScheduleRegistryOverrideUsed = $true
        }


        if ($null -ne $ComponentRegistry.SpecificMonths)
        {
            $RawSpecificMonths =
                [string]$ComponentRegistry.SpecificMonths


            $ParsedSpecificMonths = @(
                $RawSpecificMonths `
                    -split ',' |
                    ForEach-Object {
                        $_.Trim()
                    } |
                    Where-Object {
                        -not [string]::IsNullOrWhiteSpace($_)
                    } |
                    ForEach-Object {

                        if ($_ -notmatch '^\d+$')
                        {
                            throw "Invalid SpecificMonths entry [$_]."
                        }

                        [int]$_
                    }
            )


            $InvalidMonths = @(
                $ParsedSpecificMonths |
                    Where-Object {
                        $_ -lt 1 -or
                        $_ -gt 12
                    }
            )


            if ($InvalidMonths.Count -gt 0)
            {
                throw "SpecificMonths contains value(s) outside the valid range 1-12: [$($InvalidMonths -join ', ')]."
            }


            $ScheduleConfig.SpecificMonths =
                $ParsedSpecificMonths

            $ScheduleRegistryOverrideUsed = $true
        }


        $RawWeeksOfMonth = $null

        if ($null -ne $ComponentRegistry.WeeksOfMonth)
        {
            $RawWeeksOfMonth = [string]$ComponentRegistry.WeeksOfMonth
        }

        if (-not [string]::IsNullOrWhiteSpace($RawWeeksOfMonth))
        {
            $ParsedWeeksOfMonth = @(
                $RawWeeksOfMonth -split ',' |
                    ForEach-Object { $_.Trim() } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    ForEach-Object {
                        $ParsedWeek = 0
                        if (-not [int]::TryParse($_, [ref]$ParsedWeek))
                        {
                            throw "Invalid WeeksOfMonth entry [$_.] Use comma-separated values from 1-5 or -1 for Last."
                        }
                        if ($ParsedWeek -notin @(-1,1,2,3,4,5))
                        {
                            throw "WeeksOfMonth contains invalid value [$ParsedWeek]. Valid values are 1-5 and -1 for Last."
                        }
                        $ParsedWeek
                    } |
                    Select-Object -Unique
            )

            if ($ParsedWeeksOfMonth.Count -eq 0)
            {
                throw "WeeksOfMonth must contain at least one value."
            }

            $ScheduleConfig.WeeksOfMonth = $ParsedWeeksOfMonth
            $ScheduleRegistryOverrideUsed = $true
        }


        if ($null -ne $ComponentRegistry.WeekParity)
        {
            $ScheduleConfig.WeekParity =
                [string]$ComponentRegistry.WeekParity

            $ScheduleRegistryOverrideUsed = $true
        }


        if ($null -ne $ComponentRegistry.DayOfWeek)
        {
            $ScheduleConfig.DayOfWeek =
                [string]$ComponentRegistry.DayOfWeek

            $ScheduleRegistryOverrideUsed = $true
        }


        if ($null -ne $ComponentRegistry.RunOnOrAfter)
        {
            $RawRunOnOrAfter =
                $ComponentRegistry.RunOnOrAfter


            if ($RawRunOnOrAfter -is [bool])
            {
                $ScheduleConfig.RunOnOrAfter =
                    [bool]$RawRunOnOrAfter
            }
            elseif (
                $RawRunOnOrAfter -is [int] -or
                $RawRunOnOrAfter -is [long]
            )
            {
                $ScheduleConfig.RunOnOrAfter =
                    ([int64]$RawRunOnOrAfter -ne 0)
            }
            else
            {
                switch -Regex (
                    [string]$RawRunOnOrAfter
                )
                {
                    '^(?i)(1|true)$'
                    {
                        $ScheduleConfig.RunOnOrAfter =
                            $true
                    }

                    '^(?i)(0|false)$'
                    {
                        $ScheduleConfig.RunOnOrAfter =
                            $false
                    }

                    default
                    {
                        throw "Invalid RunOnOrAfter registry value [$RawRunOnOrAfter]."
                    }
                }
            }


            $ScheduleRegistryOverrideUsed =
                $true
        }
    }
    catch
    {
        Write-Host ""
        Write-Host "ERROR: Invalid DriverEvaluator registry schedule configuration." `
            -ForegroundColor Red

        Write-Host $_.Exception.Message

        exit 1
    }
}


# ============================================================
# Schedule Calculation
# ============================================================

function Get-DeltaScheduleState
{
    param
    (
        [Parameter(Mandatory)]
        [hashtable]$Config,

        [datetime]$Date = (Get-Date)
    )


    $Today =
        $Date.Date


    $ValidDays =
        [System.Enum]::GetNames(
            [System.DayOfWeek]
        )


    if ($Config.DayOfWeek -notin $ValidDays)
    {
        throw "Invalid DayOfWeek [$($Config.DayOfWeek)]."
    }


    $TargetDayOfWeek =
        [System.DayOfWeek]::$($Config.DayOfWeek)


    # --------------------------------------------------------
    # Monthly
    # --------------------------------------------------------

    if ($Config.ScheduleMode -eq "Monthly")
    {
        switch ($Config.MonthMode)
        {
            "All"
            {
                $MonthAllowed =
                    $true
            }

            "Even"
            {
                $MonthAllowed =
                    (($Today.Month % 2) -eq 0)
            }

            "Odd"
            {
                $MonthAllowed =
                    (($Today.Month % 2) -ne 0)
            }

            "Specific"
            {
                $MonthAllowed =
                    ($Today.Month -in $Config.SpecificMonths)
            }

            default
            {
                throw "Invalid MonthMode [$($Config.MonthMode)]."
            }
        }


        $BasePeriodId =
            $Today.ToString("yyyy-MM")


        if (-not $MonthAllowed)
        {
            return [PSCustomObject]@{
                Eligible     = $false
                PeriodId     = $BasePeriodId
                TargetDate   = $null
                Reason       = "Current month is excluded by schedule configuration."
                ScheduleMode = "Monthly"
            }
        }


        $FirstDayOfMonth = Get-Date `
            -Year $Today.Year `
            -Month $Today.Month `
            -Day 1


        $WeeksOfMonth = @($Config.WeeksOfMonth)
        if ($WeeksOfMonth.Count -eq 0)
        {
            throw "WeeksOfMonth must contain at least one value."
        }


        $Occurrences = @(
            foreach ($WeekOfMonth in $WeeksOfMonth)
            {
                if ($WeekOfMonth -notin @(-1,1,2,3,4,5))
                {
                    throw "WeeksOfMonth contains invalid value [$WeekOfMonth]. Valid values are 1-5 and -1 for Last."
                }

                if ($WeekOfMonth -eq -1)
                {
                    $LastDayOfMonth = $FirstDayOfMonth.AddMonths(1).AddDays(-1)
                    $DaysBack = (
                        [int]$LastDayOfMonth.DayOfWeek -
                        [int]$TargetDayOfWeek +
                        7
                    ) % 7
                    $OccurrenceDate = $LastDayOfMonth.AddDays(-$DaysBack).Date
                    $OccurrenceId = "WL"
                }
                else
                {
                    $DaysUntilTarget = (
                        [int]$TargetDayOfWeek -
                        [int]$FirstDayOfMonth.DayOfWeek +
                        7
                    ) % 7
                    $OccurrenceDate = $FirstDayOfMonth.AddDays(
                        $DaysUntilTarget + (($WeekOfMonth - 1) * 7)
                    ).Date
                    if ($OccurrenceDate.Month -ne $Today.Month)
                    {
                        continue
                    }
                    $OccurrenceId = "W$WeekOfMonth"
                }

                [PSCustomObject]@{
                    Week       = $WeekOfMonth
                    Id         = $OccurrenceId
                    TargetDate = $OccurrenceDate
                }
            }
        ) | Sort-Object TargetDate


        if ($Occurrences.Count -eq 0)
        {
            return [PSCustomObject]@{
                Eligible     = $false
                PeriodId     = $BasePeriodId
                TargetDate   = $null
                Reason       = "Configured weekday occurrence does not exist in this month."
                ScheduleMode = "Monthly"
            }
        }


        if ($Config.RunOnOrAfter)
        {
            # Catch-up semantics: use the latest configured occurrence already reached.
            # Once a later occurrence is reached, an older missed occurrence is obsolete.
            $SelectedOccurrence = @(
                $Occurrences | Where-Object { $_.TargetDate -le $Today }
            ) | Select-Object -Last 1

            $Eligible = ($null -ne $SelectedOccurrence)
        }
        else
        {
            # Exact-day semantics: a missed occurrence is not caught up later.
            $SelectedOccurrence = @(
                $Occurrences | Where-Object { $_.TargetDate -eq $Today }
            ) | Select-Object -First 1

            $Eligible = ($null -ne $SelectedOccurrence)
        }


        if ($null -ne $SelectedOccurrence)
        {
            $PeriodId = "$BasePeriodId-$($SelectedOccurrence.Id)"
            $TargetDate = $SelectedOccurrence.TargetDate
        }
        else
        {
            $PeriodId = $BasePeriodId
            $TargetDate = ($Occurrences | Select-Object -First 1).TargetDate
        }


        return [PSCustomObject]@{
            Eligible     = $Eligible
            PeriodId     = $PeriodId
            TargetDate   = $TargetDate
            Reason       = $(if ($Eligible) {
                "Monthly schedule is eligible for occurrence [$($SelectedOccurrence.Id)]."
            } else {
                "No configured monthly occurrence is eligible today."
            })
            ScheduleMode = "Monthly"
        }
    }


    # --------------------------------------------------------
    # Weekly
    # --------------------------------------------------------

    if ($Config.ScheduleMode -eq "Weekly")
    {
        $Calendar =
            [System.Globalization.CultureInfo]::InvariantCulture.Calendar


        $WeekNumber =
            $Calendar.GetWeekOfYear(
                $Today,
                [System.Globalization.CalendarWeekRule]::FirstFourDayWeek,
                [System.DayOfWeek]::Monday
            )


        switch ($Config.WeekParity)
        {
            "All"
            {
                $WeekAllowed =
                    $true
            }

            "Even"
            {
                $WeekAllowed =
                    (($WeekNumber % 2) -eq 0)
            }

            "Odd"
            {
                $WeekAllowed =
                    (($WeekNumber % 2) -ne 0)
            }

            default
            {
                throw "Invalid WeekParity [$($Config.WeekParity)]."
            }
        }


        $DaysSinceMonday = (
            [int]$Today.DayOfWeek -
            [int][System.DayOfWeek]::Monday +
            7
        ) % 7


        $WeekStart =
            $Today.AddDays(
                -$DaysSinceMonday
            )


        $TargetOffset = (
            [int]$TargetDayOfWeek -
            [int][System.DayOfWeek]::Monday +
            7
        ) % 7


        $TargetDate =
            $WeekStart.AddDays(
                $TargetOffset
            ).Date


        $PeriodId =
            "{0}-W{1:D2}" -f
                $Today.Year,
                $WeekNumber


        if (-not $WeekAllowed)
        {
            return [PSCustomObject]@{
                Eligible     = $false
                PeriodId     = $PeriodId
                TargetDate   = $TargetDate
                Reason       = "Current week is excluded by WeekParity configuration."
                ScheduleMode = "Weekly"
            }
        }


        if ($Config.RunOnOrAfter)
        {
            $Eligible =
                ($Today -ge $TargetDate)
        }
        else
        {
            $Eligible =
                ($Today -eq $TargetDate)
        }


        return [PSCustomObject]@{
            Eligible =
                $Eligible

            PeriodId =
                $PeriodId

            TargetDate =
                $TargetDate

            Reason =
                $(if ($Eligible)
                {
                    "Weekly schedule is eligible."
                }
                else
                {
                    "Scheduled weekday has not been reached."
                })

            ScheduleMode =
                "Weekly"
        }
    }


    throw "Invalid ScheduleMode [$($Config.ScheduleMode)]."
}


# ============================================================
# Calculate Schedule State
# ============================================================

try
{
    $ScheduleState =
        Get-DeltaScheduleState `
            -Config $ScheduleConfig `
            -Date (Get-Date)
}
catch
{
    Write-Host ""
    Write-Host "ERROR: Invalid schedule configuration." `
        -ForegroundColor Red

    Write-Host $_.Exception.Message

    exit 1
}


$PeriodId =
    $ScheduleState.PeriodId


# ============================================================
# Artifact Paths
# ============================================================

$SuccessMarker = Join-Path `
    $SnapshotFolder `
    "$ArtifactPrefix-$PeriodId.success"


$FailedMarker = Join-Path `
    $SnapshotFolder `
    "$ArtifactPrefix-$PeriodId.failed"


$SPListFile = Join-Path `
    $SnapshotFolder `
    "$ArtifactPrefix-$PeriodId.splist.txt"


$ManifestFile = Join-Path `
    $SnapshotFolder `
    "$ArtifactPrefix-$PeriodId.manifest.json"


# ============================================================
# Early Exit
# ============================================================

if (
    -not $ForceRun -and
    -not $ScheduleState.Eligible
)
{
    exit 0
}


if (
    -not $ForceRun -and
    (Test-Path -Path $SuccessMarker -PathType Leaf)
)
{
    exit 0
}


# ============================================================
# Runtime State
# ============================================================

$Mutex =
    New-Object System.Threading.Mutex(
        $false,
        $MutexName
    )


$MutexAcquired =
    $false


$LogFile =
    $null


$HPIAVersion =
    "Unknown"


$RecommendationCount =
    0

$DetectedRecommendationCount =
    0

$ExcludedRecommendationCount =
    0

$ExcludedRecommendations =
    @()


$ExecutionId =
    [guid]::NewGuid().ToString()


$ExecutionStopwatch =
    [System.Diagnostics.Stopwatch]::StartNew()


$HPIAStopwatch =
    $null


$HPIADurationSeconds =
    $null


$HPIAExitCode =
    $null


$ExecutionOutcome =
    "Failed"


try
{
    # ========================================================
    # Mutex
    # ========================================================

    $MutexAcquired =
        $Mutex.WaitOne(0)


    if (-not $MutexAcquired)
    {
        exit 0
    }


    # ========================================================
    # Required Folders
    # ========================================================

    if (-not (Test-Path -Path $ReportFolder -PathType Container))
    {
        New-Item `
            -Path $ReportFolder `
            -ItemType Directory `
            -Force `
            -ErrorAction Stop |
            Out-Null
    }

    if (-not (Test-Path -Path $SnapshotFolder -PathType Container))
    {
        New-Item `
            -Path $SnapshotFolder `
            -ItemType Directory `
            -Force `
            -ErrorAction Stop |
            Out-Null
    }
# ========================================================
    # Logging
    # ========================================================

    $LogFile = Join-Path `
        $ReportFolder `
        "$ScriptName-$env:COMPUTERNAME.log"


    function Write-Log
    {
        param
        (
            [Parameter(Mandatory)]
            [string]$Message,

            [ValidateSet(
                "INFO",
                "WARNING",
                "ERROR"
            )]
            [string]$Level = "INFO"
        )


        $DateTime =
            Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"


        Add-Content `
            -Path $LogFile `
            -Value "[$DateTime] [$Level] $Message" `
            -Encoding UTF8
    }


    if (Test-Path -Path $LogFile -PathType Leaf)
    {
        Add-Content `
            -Path $LogFile `
            -Value "" `
            -Encoding UTF8

        Add-Content `
            -Path $LogFile `
            -Value "" `
            -Encoding UTF8
    }


    # ========================================================
    # HPIA Exit Code Description
    # ========================================================

    function Get-HPIAExitCodeDescription
    {
        param
        (
            [Parameter(Mandatory)]
            [int]$ExitCode
        )


        switch ($ExitCode)
        {
            0
            {
                return "Successful execution"
            }

            256
            {
                return "Analysis returned no recommendations"
            }

            257
            {
                return "No recommendations were selected"
            }

            4096
            {
                return "Platform is not supported"
            }

            4097
            {
                return "Invalid parameters"
            }

            4098
            {
                return "No Internet connection"
            }

            4099
            {
                return "Invalid SoftPaq number in SPList"
            }

            4102
            {
                return "TLS 1.2 or higher is required"
            }

            4103
            {
                return "Complete request could not be sent to remote server"
            }

            8192
            {
                return "HPIA operation failed"
            }

            8194
            {
                return "Output folder could not be created"
            }

            8196
            {
                return "Supported platforms list download failed"
            }

            8197
            {
                return "Knowledge base download failed"
            }

            8199
            {
                return "SoftPaq download failed"
            }

            default
            {
                return "Unknown or unhandled HPIA exit code"
            }
        }
    }


    # ========================================================
    # Snapshot Retention
    # ========================================================

    function Invoke-DeltaSnapshotRetention
    {
        if ($SnapshotRetentionCount -lt 1)
        {
            return
        }


        $Manifests = @(
            Get-ChildItem `
                -Path $SnapshotFolder `
                -Filter "$ArtifactPrefix-*.manifest.json" `
                -File `
                -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending
        )


        if ($Manifests.Count -le $SnapshotRetentionCount)
        {
            Write-Log `
                -Message "Snapshot retention: [$($Manifests.Count)] snapshot(s) present. Nothing to remove."

            return
        }


        $ExpiredManifests = @(
            $Manifests |
                Select-Object -Skip $SnapshotRetentionCount
        )


        foreach ($ExpiredManifest in $ExpiredManifests)
        {
            $Pattern =
                '^' +
                [regex]::Escape($ArtifactPrefix) +
                '-(.+)\.manifest\.json$'


            if ($ExpiredManifest.Name -notmatch $Pattern)
            {
                continue
            }


            $ExpiredPeriod =
                $Matches[1]


            $ExpiredSPList = Join-Path `
                $SnapshotFolder `
                "$ArtifactPrefix-$ExpiredPeriod.splist.txt"


            $ExpiredSuccessMarker = Join-Path `
                $SnapshotFolder `
                "$ArtifactPrefix-$ExpiredPeriod.success"


            $ExpiredFailedMarker = Join-Path `
                $SnapshotFolder `
                "$ArtifactPrefix-$ExpiredPeriod.failed"


            $ExpiredDeployedMarker = Join-Path `
                $SnapshotFolder `
                "$ArtifactPrefix-$ExpiredPeriod.deployed"


            $ExpiredArtifacts = @(
                [PSCustomObject]@{
                    Path = $ExpiredManifest.FullName
                    Description = "manifest"
                }
                [PSCustomObject]@{
                    Path = $ExpiredSPList
                    Description = "SPList"
                }
                [PSCustomObject]@{
                    Path = $ExpiredSuccessMarker
                    Description = "success marker"
                }
                [PSCustomObject]@{
                    Path = $ExpiredFailedMarker
                    Description = "failed marker"
                }
                [PSCustomObject]@{
                    Path = $ExpiredDeployedMarker
                    Description = "deployed marker"
                }
            )


            foreach ($ExpiredArtifact in $ExpiredArtifacts)
            {
                if (Test-Path -Path $ExpiredArtifact.Path -PathType Leaf)
                {
                    Write-Log `
                        -Message "Removing expired snapshot $($ExpiredArtifact.Description): [$($ExpiredArtifact.Path)]"


                    Remove-Item `
                        -Path $ExpiredArtifact.Path `
                        -Force `
                        -ErrorAction Stop
                }
            }
        }
    }


    # ========================================================
    # Success Marker
    # ========================================================

    function Set-DeltaSuccess
    {
        param
        (
            [Parameter(Mandatory)]
            [int]$ExitCode,

            [Parameter(Mandatory)]
            [string]$Reason,

            [Parameter(Mandatory)]
            [string]$HPIAVersion,

            [Parameter(Mandatory)]
            [int]$RecommendationCount
        )


        if (Test-Path -Path $FailedMarker -PathType Leaf)
        {
            Remove-Item `
                -Path $FailedMarker `
                -Force `
                -ErrorAction Stop
        }




        $MarkerContent = @(
            "Timestamp=$((Get-Date).ToString('o'))"
            "Status=Success"
            "ExecutionId=$ExecutionId"
            "ExitCode=$ExitCode"
            "Reason=$Reason"
            "ComputerName=$env:COMPUTERNAME"
            "ComponentVersion=$ComponentVersion"
            "HPIAVersion=$HPIAVersion"
            "PowerShellVersion=$($PSVersionTable.PSVersion)"
            "ScheduleMode=$($ScheduleState.ScheduleMode)"
            "SchedulePeriod=$PeriodId"
            "DetectedRecommendationCount=$DetectedRecommendationCount"
            "ExcludedRecommendationCount=$ExcludedRecommendationCount"
            "RecommendationCount=$RecommendationCount"
            "SPList=$SPListFile"
            "Manifest=$ManifestFile"
        )


        Set-Content `
            -Path $SuccessMarker `
            -Value $MarkerContent `
            -Encoding UTF8 `
            -ErrorAction Stop


        Write-Log `
            -Message "Success marker created: [$SuccessMarker]"
    }


    # ========================================================
    # Failure Marker
    # ========================================================

    function Set-DeltaFailure
    {
        param
        (
            [Parameter(Mandatory)]
            [int]$ExitCode,

            [Parameter(Mandatory)]
            [string]$Reason,

            [string]$HPIAVersion = "Unknown"
        )


        if (Test-Path -Path $SuccessMarker -PathType Leaf)
        {
            Remove-Item `
                -Path $SuccessMarker `
                -Force `
                -ErrorAction Stop
        }




        $MarkerContent = @(
            "Timestamp=$((Get-Date).ToString('o'))"
            "Status=Failed"
            "ExecutionId=$ExecutionId"
            "ExitCode=$ExitCode"
            "Reason=$Reason"
            "ComputerName=$env:COMPUTERNAME"
            "ComponentVersion=$ComponentVersion"
            "HPIAVersion=$HPIAVersion"
            "PowerShellVersion=$($PSVersionTable.PSVersion)"
            "ScheduleMode=$($ScheduleState.ScheduleMode)"
            "SchedulePeriod=$PeriodId"
        )


        Set-Content `
            -Path $FailedMarker `
            -Value $MarkerContent `
            -Encoding UTF8 `
            -ErrorAction Stop


        Write-Log `
            -Message "Failed marker created/updated: [$FailedMarker]" `
            -Level "WARNING"
    }


    # ========================================================
    # Execution Information
    # ========================================================

    Write-Log `
        -Message "$FrameworkName / $ScriptName started."


    Write-Log `
        -Message "Component version: [$ComponentVersion]"


    if ($ForceRun)
    {
        $ExecutionMode = "ForceRun"
    }
    else
    {
        $ExecutionMode = "Normal"
    }


    Write-Log `
        -Message "Execution mode: [$ExecutionMode]"
Write-Log `
        -Message "Execution ID: [$ExecutionId]"


    Write-Log `
        -Message "Framework enabled: [$FrameworkEnabled]"


    Write-Log `
        -Message "Framework enabled source: [$FrameworkEnabledSource]"


    Write-Log `
        -Message "Framework ExcludeSoftPaqs: [$($ConfiguredExcludeSoftPaqs -join ',')]"


    if (
        -not $FrameworkEnabled -and
        $ForceRun
    )
    {
        Write-Log `
            -Message "Framework is disabled by registry configuration, but ForceRun overrides the disabled state." `
            -Level "WARNING"
    }


    Write-Log `
        -Message "Computer name: [$env:COMPUTERNAME]"


    Write-Log `
        -Message "Running account: [$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)]"


    Write-Log `
        -Message "PowerShell version: [$($PSVersionTable.PSVersion)]"


    Write-Log `
        -Message "Framework registry path: [$FrameworkRegistryPath]"


    Write-Log `
        -Message "Component registry path: [$ComponentRegistryPath]"


    Write-Log `
        -Message "Schedule mode: [$($ScheduleState.ScheduleMode)]"


    Write-Log `
        -Message "Schedule period: [$PeriodId]"


    Write-Log `
        -Message "Schedule status: [$($ScheduleState.Reason)]"


    if ($ScheduleRegistryOverrideUsed)
    {
        $ScheduleConfigurationSource =
            "Registry override + built-in defaults"
    }
    else
    {
        $ScheduleConfigurationSource =
            "Built-in defaults"
    }


    Write-Log `
        -Message "Schedule configuration source: [$ScheduleConfigurationSource]"


    Write-Log `
        -Message "Effective schedule configuration: ScheduleMode=[$($ScheduleConfig.ScheduleMode)], MonthMode=[$($ScheduleConfig.MonthMode)], SpecificMonths=[$($ScheduleConfig.SpecificMonths -join ',')], WeeksOfMonth=[$($ScheduleConfig.WeeksOfMonth -join ',')], WeekParity=[$($ScheduleConfig.WeekParity)], DayOfWeek=[$($ScheduleConfig.DayOfWeek)], RunOnOrAfter=[$($ScheduleConfig.RunOnOrAfter)]"


    if ($null -ne $ScheduleState.TargetDate)
    {
        Write-Log `
            -Message "Schedule target date: [$($ScheduleState.TargetDate.ToString('yyyy-MM-dd'))]"
    }


    if ($ForceRun)
    {
        Write-Log `
            -Message "ForceRun specified. Enabled state, schedule eligibility and success marker checks were bypassed."
    }
    elseif (Test-Path -Path $FailedMarker -PathType Leaf)
    {
        Write-Log `
            -Message "Previous failure exists for this mode and period. Retrying." `
            -Level "WARNING"
    }


    # ========================================================
    # Ensure HPIA Is Current
    # ========================================================

    Invoke-HPIAInstallOrUpdate


    # ========================================================
    # Verify HPIA
    # ========================================================

    if (-not (Test-Path -Path $HPIAExe -PathType Leaf))
    {
        $FailureReason =
            "HP Image Assistant not found: $HPIAExe"


        Write-Log `
            -Message $FailureReason `
            -Level "ERROR"


        Set-DeltaFailure `
            -ExitCode 1 `
            -Reason $FailureReason


        exit 1
    }


    $HPIAVersion = (
        Get-Item `
            -Path $HPIAExe `
            -ErrorAction Stop
    ).VersionInfo.FileVersion


    if ([string]::IsNullOrWhiteSpace($HPIAVersion))
    {
        $HPIAVersion =
            "Unknown"
    }


    Write-Log `
        -Message "HP Image Assistant version: [$HPIAVersion]"


    # ========================================================
    # Capture HPIA JSON State
    # ========================================================

    $ReportsBefore =
        @{}


    Get-ChildItem `
        -Path $ReportFolder `
        -Filter "*.json" `
        -File `
        -ErrorAction SilentlyContinue |
        ForEach-Object {

            $ReportsBefore[$_.FullName] = @{
                LastWriteTimeUtc = $_.LastWriteTimeUtc
                Length           = $_.Length
            }
        }


    Write-Log `
        -Message "Captured state of [$($ReportsBefore.Count)] existing HPIA JSON report(s)."


    # ========================================================
    # HPIA Arguments
    # ========================================================

    $HPIAArguments = @(
        "/Operation:Analyze"
        "/Category:Drivers,Software,Firmware,Accessories"
        "/Selection:All"
        "/InstallType:AutoInstallable"
        "/Action:List"
        "/Noninteractive"
        "/Debug"
        "/ReportFolder:$ReportFolder"
    )
# ========================================================
    # Start HPIA
    # ========================================================

    Write-Log `
        -Message "Starting HP Image Assistant Analyze / List operation."


    $HPIAStopwatch =
        [System.Diagnostics.Stopwatch]::StartNew()


    $Process = Start-Process `
        -FilePath $HPIAExe `
        -ArgumentList $HPIAArguments `
        -PassThru `
        -WindowStyle Hidden `
        -ErrorAction Stop


    # ========================================================
    # Wait With Timeout
    # ========================================================

    $TimeoutMilliseconds =
        $HPIATimeoutMinutes *
        60 *
        1000


    $Completed =
        $Process.WaitForExit(
            $TimeoutMilliseconds
        )


    if ($null -ne $HPIAStopwatch)
    {
        $HPIAStopwatch.Stop()

        $HPIADurationSeconds =
            [math]::Round(
                $HPIAStopwatch.Elapsed.TotalSeconds,
                2
            )
    }


    if (-not $Completed)
    {
        Write-Log `
            -Message "HPIA exceeded timeout of [$HPIATimeoutMinutes] minutes." `
            -Level "ERROR"


        try
        {
            $Process.Kill()
            $Process.WaitForExit()
        }
        catch
        {
            Write-Log `
                -Message "Unable to terminate timed-out HPIA process: $($_.Exception.Message)" `
                -Level "ERROR"
        }


        Set-DeltaFailure `
            -ExitCode 1 `
            -Reason "HPIA execution timeout" `
            -HPIAVersion $HPIAVersion


        exit 1
    }


    # ========================================================
    # HPIA Process Result
    # ========================================================

    $HPIAExitCode =
        $Process.ExitCode


    $HPIAExitDescription =
        Get-HPIAExitCodeDescription `
            -ExitCode $HPIAExitCode


    Write-Log `
        -Message "HP Image Assistant finished with exit code [$HPIAExitCode]."


    Write-Log `
        -Message "HPIA process result: [$HPIAExitDescription]"


    # ========================================================
    # Locate New / Modified HPIA JSON Report
    # ========================================================

    $ChangedReports =
        @()


    $ReportsAfter = @(
        Get-ChildItem `
            -Path $ReportFolder `
            -Filter "*.json" `
            -File `
            -ErrorAction SilentlyContinue
    )


    foreach ($Report in $ReportsAfter)
    {
        $IsChanged =
            $false


        if (-not $ReportsBefore.ContainsKey($Report.FullName))
        {
            $IsChanged =
                $true
        }
        else
        {
            $Previous =
                $ReportsBefore[$Report.FullName]


            if (
                $Report.LastWriteTimeUtc -ne $Previous.LastWriteTimeUtc -or
                $Report.Length -ne $Previous.Length
            )
            {
                $IsChanged =
                    $true
            }
        }


        if ($IsChanged)
        {
            try
            {
                $Content = Get-Content `
                    -Path $Report.FullName `
                    -Raw `
                    -ErrorAction Stop |
                    ConvertFrom-Json `
                        -ErrorAction Stop


                if ($null -eq $Content.HPIA)
                {
                    continue
                }


                $LastAnalyzedDateString =
                    [string]$Content.HPIA.LastAnalyzedDate


                if ([string]::IsNullOrWhiteSpace($LastAnalyzedDateString))
                {
                    continue
                }


                $LastAnalyzedDate =
                    [DateTimeOffset]::Parse(
                        $LastAnalyzedDateString,
                        [System.Globalization.CultureInfo]::InvariantCulture,
                        [System.Globalization.DateTimeStyles]::RoundtripKind
                    )


                $ChangedReports +=
                    [PSCustomObject]@{
                        File       = $Report
                        Content    = $Content
                        AnalyzedAt = $LastAnalyzedDate
                    }
            }
            catch
            {
                Write-Log `
                    -Message "Unable to parse changed JSON report [$($Report.FullName)]: $($_.Exception.Message)" `
                    -Level "WARNING"
            }
        }
    }


    if ($ChangedReports.Count -eq 0)
    {
        $FailureReason =
            "No new or modified HPIA JSON report could be validated for this execution."


        Write-Log `
            -Message $FailureReason `
            -Level "ERROR"


        Set-DeltaFailure `
            -ExitCode 1 `
            -Reason $FailureReason `
            -HPIAVersion $HPIAVersion


        exit 1
    }


    # ========================================================
    # Select Newest Report
    # ========================================================

    $SelectedReport =
        $ChangedReports |
            Sort-Object AnalyzedAt -Descending |
            Select-Object -First 1


    $ReportPath =
        $SelectedReport.File.FullName


    $ReportJson =
        $SelectedReport.Content


    # ========================================================
    # HPIA JSON State
    # ========================================================

    $ReportExitCode =
        [int]$ReportJson.HPIA.ExitCode


    $ReportStatus =
        [string]$ReportJson.HPIA.LastOperationStatus


    $ReportOperation =
        [string]$ReportJson.HPIA.HPIAOperation


    $ReportStatusDesc =
        [string]$ReportJson.HPIA.LastOperationStatusDesc


    $ReportLastOperation =
        [string]$ReportJson.HPIA.LastOperation


    Write-Log `
        -Message "Selected HPIA report: [$ReportPath]"


    Write-Log `
        -Message "JSON ExitCode: [$ReportExitCode]"


    Write-Log `
        -Message "JSON HPIAOperation: [$ReportOperation]"


    Write-Log `
        -Message "JSON LastOperation: [$ReportLastOperation]"


    Write-Log `
        -Message "JSON LastOperationStatus: [$ReportStatus]"


    Write-Log `
        -Message "JSON LastOperationStatusDesc: [$ReportStatusDesc]"


    # ========================================================
    # Validate HPIA Process
    # ========================================================

    if ($HPIAExitCode -notin $AcceptedHPIAExitCodes)
    {
        $FailureReason =
            "HPIA process failed with exit code [$HPIAExitCode]: $HPIAExitDescription"


        Write-Log `
            -Message $FailureReason `
            -Level "ERROR"


        Set-DeltaFailure `
            -ExitCode $HPIAExitCode `
            -Reason $FailureReason `
            -HPIAVersion $HPIAVersion


        exit $HPIAExitCode
    }


    # ========================================================
    # Validate HPIA JSON
    # ========================================================

    if ($ReportExitCode -notin $AcceptedHPIAExitCodes)
    {
        $FailureReason =
            "HPIA JSON report indicates failure with exit code [$ReportExitCode]."


        Write-Log `
            -Message $FailureReason `
            -Level "ERROR"


        Set-DeltaFailure `
            -ExitCode $ReportExitCode `
            -Reason $FailureReason `
            -HPIAVersion $HPIAVersion


        exit 1
    }


    if ($ReportStatus -ne "Success")
    {
        $FailureReason =
            "HPIA JSON report status [$ReportStatus] is not [Success]."


        Write-Log `
            -Message $FailureReason `
            -Level "ERROR"


        Set-DeltaFailure `
            -ExitCode $ReportExitCode `
            -Reason $FailureReason `
            -HPIAVersion $HPIAVersion


        exit 1
    }


    if ($ReportOperation -ne $ExpectedHPIAOperation)
    {
        $FailureReason =
            "Unexpected HPIA operation [$ReportOperation]. Expected [$ExpectedHPIAOperation]."


        Write-Log `
            -Message $FailureReason `
            -Level "ERROR"


        Set-DeltaFailure `
            -ExitCode $ReportExitCode `
            -Reason $FailureReason `
            -HPIAVersion $HPIAVersion


        exit 1
    }


    # ========================================================
    # Recommendations
    # ========================================================

    $RawRecommendations =
        $ReportJson.HPIA.Recommendations


    if ($null -eq $RawRecommendations)
    {
        $DetectedRecommendations = @()
    }
    else
    {
        $DetectedRecommendations = @($RawRecommendations)
    }


    $DetectedRecommendationCount =
        $DetectedRecommendations.Count

    $Recommendations = @()
    $ExcludedRecommendations = @()


    foreach ($Recommendation in $DetectedRecommendations)
    {
        $RecommendationSoftPaqId =
            [string]$Recommendation.SoftPaqID

        $RecommendationSoftPaq =
            $RecommendationSoftPaqId -replace '^(?i)sp', ''


        if (
            -not [string]::IsNullOrWhiteSpace($RecommendationSoftPaq) -and
            $RecommendationSoftPaq -in $ConfiguredExcludeSoftPaqs
        )
        {
            $ExcludedRecommendations += $Recommendation

            Write-Log `
                -Message "Excluded recommendation: [$RecommendationSoftPaqId] [$([string]$Recommendation.Name)]" `
                -Level "WARNING"

            continue
        }


        $Recommendations += $Recommendation
    }


    $ExcludedRecommendationCount =
        $ExcludedRecommendations.Count

    $RecommendationCount =
        $Recommendations.Count


    Write-Log `
        -Message "HPIA recommendation count before exclusions: [$DetectedRecommendationCount]"

    Write-Log `
        -Message "Excluded recommendation count: [$ExcludedRecommendationCount]"

    Write-Log `
        -Message "Effective recommendation count: [$RecommendationCount]"


    # ========================================================
    # Extract SoftPaq Numbers
    # ========================================================

    $SoftPaqNumbers = @(
        foreach ($Recommendation in $Recommendations)
        {
            $SoftPaqId =
                [string]$Recommendation.SoftPaqID


            if ([string]::IsNullOrWhiteSpace($SoftPaqId))
            {
                continue
            }


            $RawNumber =
                $SoftPaqId -replace '^(?i)sp', ''


            if ($RawNumber -match '^\d+$')
            {
                $RawNumber
            }
        }
    )


    Write-Log `
        -Message "Recommendation count: [$RecommendationCount]"


    Write-Log `
        -Message "Extracted SoftPaq number count: [$($SoftPaqNumbers.Count)]"


    if ($RecommendationCount -ne $SoftPaqNumbers.Count)
    {
        throw "Recommendation count [$RecommendationCount] does not match valid SoftPaq number count [$($SoftPaqNumbers.Count)]."
    }


    $UniqueSoftPaqNumbers = @(
        $SoftPaqNumbers |
            Select-Object -Unique
    )


    if ($UniqueSoftPaqNumbers.Count -ne $RecommendationCount)
    {
        throw "Duplicate SoftPaq IDs detected in HPIA recommendations."
    }


    $SoftPaqNumbers =
        $UniqueSoftPaqNumbers


    # ========================================================
    # Recommendation Metadata
    # ========================================================

    $ManifestRecommendations = @(
        foreach ($Recommendation in $Recommendations)
        {
            $SoftPaqId =
                [string]$Recommendation.SoftPaqID


            $SoftPaqNumber =
                $SoftPaqId -replace '^(?i)sp', ''


            [ordered]@{
                SoftPaq =
                    $SoftPaqNumber

                SoftPaqID =
                    $SoftPaqId

                RecommendationId =
                    [string]$Recommendation.RecommendationId

                Name =
                    [string]$Recommendation.Name

                RecommendationValue =
                    [string]$Recommendation.RecommendationValue

                Severity =
                    [string]$Recommendation.Severity

                SSMCompliant =
                    [string]$Recommendation.SSMCompliant

                DPBCompliant =
                    [string]$Recommendation.DPBCompliant

                Url =
                    [string]$Recommendation.Url

                ReleaseNotesUrl =
                    [string]$Recommendation.ReleaseNotesUrl

                MetadataUrl =
                    [string]$Recommendation.MetadataUrl

                Comments =
                    [string]$Recommendation.Comments
            }
        }
    )


    $ManifestExcludedRecommendations = @(
        foreach ($Recommendation in $ExcludedRecommendations)
        {
            $SoftPaqId =
                [string]$Recommendation.SoftPaqID

            $SoftPaqNumber =
                $SoftPaqId -replace '^(?i)sp', ''

            [ordered]@{
                SoftPaq             = $SoftPaqNumber
                SoftPaqID           = $SoftPaqId
                RecommendationId    = [string]$Recommendation.RecommendationId
                Name                = [string]$Recommendation.Name
                RecommendationValue = [string]$Recommendation.RecommendationValue
                Severity            = [string]$Recommendation.Severity
                Comments            = [string]$Recommendation.Comments
            }
        }
    )


    # ========================================================
    # Transactional Snapshot
    # ========================================================

    $SPListTempFile =
        "$SPListFile.tmp"


    $ManifestTempFile =
        "$ManifestFile.tmp"


    foreach ($TempFile in @(
        $SPListTempFile,
        $ManifestTempFile
    ))
    {
        if (Test-Path -Path $TempFile -PathType Leaf)
        {
            Remove-Item `
                -Path $TempFile `
                -Force `
                -ErrorAction Stop
        }
    }


    # ========================================================
    # SPList
    # ========================================================

    if ($RecommendationCount -gt 0)
    {
        $SoftPaqNumbers |
            Set-Content `
                -Path $SPListTempFile `
                -Encoding ASCII `
                -ErrorAction Stop
    }
    else
    {
        New-Item `
            -Path $SPListTempFile `
            -ItemType File `
            -Force `
            -ErrorAction Stop |
            Out-Null
    }


    $WrittenSPList = @(
        Get-Content `
            -Path $SPListTempFile `
            -ErrorAction Stop |
            ForEach-Object {
                $_.Trim()
            } |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_)
            }
    )


    if ($WrittenSPList.Count -ne $RecommendationCount)
    {
        throw "Generated SPList validation failed. Expected [$RecommendationCount] entries, found [$($WrittenSPList.Count)]."
    }


    $InvalidSPListEntries = @(
        $WrittenSPList |
            Where-Object {
                $_ -notmatch '^\d+$'
            }
    )


    if ($InvalidSPListEntries.Count -gt 0)
    {
        throw "Generated SPList contains invalid entries: [$($InvalidSPListEntries -join ', ')]."
    }


    # ========================================================
    # Manifest
    # ========================================================

    $TotalDurationSeconds =
        [math]::Round(
            $ExecutionStopwatch.Elapsed.TotalSeconds,
            2
        )


    $Manifest = [ordered]@{
        Timestamp =
            $SelectedReport.AnalyzedAt.ToString("o")

        ExecutionId =
            $ExecutionId

        TotalDurationSeconds =
            $TotalDurationSeconds

        HPIADurationSeconds =
            $HPIADurationSeconds
        ComputerName =
            $env:COMPUTERNAME

        ComponentVersion =
            $ComponentVersion

        HPIAVersion =
            $HPIAVersion

        PowerShellVersion =
            $PSVersionTable.PSVersion.ToString()

        ScheduleMode =
            $ScheduleState.ScheduleMode

        SchedulePeriod =
            $PeriodId

        DetectedRecommendationCount =
            $DetectedRecommendationCount

        ExcludedRecommendationCount =
            $ExcludedRecommendationCount

        RecommendationCount =
            $RecommendationCount

        ConfiguredExcludeSoftPaqs =
            @($ConfiguredExcludeSoftPaqs)

        ExcludedSoftPaqs =
            @(
                $ExcludedRecommendations |
                    ForEach-Object {
                        ([string]$_.SoftPaqID) -replace '^(?i)sp', ''
                    }
            )

        SoftPaqs =
            @($SoftPaqNumbers)

        Recommendations =
            @($ManifestRecommendations)

        ExcludedRecommendations =
            @($ManifestExcludedRecommendations)

        HPIAReport =
            $ReportPath

        HPIAOperation =
            $ReportOperation

        HPIALastOperation =
            $ReportLastOperation

        HPIAExitCode =
            $ReportExitCode

        HPIAStatus =
            $ReportStatus

        HPIAStatusDescription =
            $ReportStatusDesc
    }
$Manifest |
        ConvertTo-Json -Depth 8 |
        Set-Content `
            -Path $ManifestTempFile `
            -Encoding UTF8 `
            -ErrorAction Stop


    # ========================================================
    # Validate Manifest
    # ========================================================

    $ManifestValidation = Get-Content `
        -Path $ManifestTempFile `
        -Raw `
        -ErrorAction Stop |
        ConvertFrom-Json `
            -ErrorAction Stop


    if (
        [int]$ManifestValidation.RecommendationCount -ne
        $RecommendationCount
    )
    {
        throw "Generated manifest RecommendationCount validation failed."
    }
# ========================================================
    # Commit Snapshot
    # ========================================================

    if (Test-Path -Path $SPListFile -PathType Leaf)
    {
        Remove-Item `
            -Path $SPListFile `
            -Force `
            -ErrorAction Stop
    }


    if (Test-Path -Path $ManifestFile -PathType Leaf)
    {
        Remove-Item `
            -Path $ManifestFile `
            -Force `
            -ErrorAction Stop
    }


    Move-Item `
        -Path $SPListTempFile `
        -Destination $SPListFile `
        -Force `
        -ErrorAction Stop


    Move-Item `
        -Path $ManifestTempFile `
        -Destination $ManifestFile `
        -Force `
        -ErrorAction Stop


    Write-Log `
        -Message "SPList committed successfully: [$SPListFile]"


    Write-Log `
        -Message "Manifest committed successfully: [$ManifestFile]"


    if ($RecommendationCount -gt 0)
    {
        Write-Log `
            -Message "Detected SoftPaqs: [$($SoftPaqNumbers -join ', ')]"
    }
    else
    {
        Write-Log `
            -Message "No SoftPaq recommendations were detected."
    }


    # ========================================================
    # Retention
    # ========================================================

    Invoke-DeltaSnapshotRetention


    # ========================================================
    # Success
    # ========================================================

    if ([string]::IsNullOrWhiteSpace($ReportStatusDesc))
    {
        $SuccessReason =
            Get-HPIAExitCodeDescription `
                -ExitCode $ReportExitCode
    }
    else
    {
        $SuccessReason =
            $ReportStatusDesc
    }


    Set-DeltaSuccess `
        -ExitCode $ReportExitCode `
        -Reason $SuccessReason `
        -HPIAVersion $HPIAVersion `
        -RecommendationCount $RecommendationCount


    Write-Log `
        -Message "$ScriptName completed successfully."


    $ExecutionOutcome =
        "Success"


    exit 0
}
catch
{
    $FailureReason =
        $_.Exception.Message


    if ($LogFile)
    {
        Write-Log `
            -Message "Unhandled error: $FailureReason" `
            -Level "ERROR"


        foreach ($TempFile in @(
            "$SPListFile.tmp",
            "$ManifestFile.tmp"
        ))
        {
            try
            {
                if (Test-Path -Path $TempFile -PathType Leaf)
                {
                    Remove-Item `
                        -Path $TempFile `
                        -Force `
                        -ErrorAction Stop
                }
            }
            catch
            {
                Write-Log `
                    -Message "Unable to remove temporary file [$TempFile]: $($_.Exception.Message)" `
                    -Level "WARNING"
            }
        }


        try
        {
            Set-DeltaFailure `
                -ExitCode 1 `
                -Reason $FailureReason `
                -HPIAVersion $HPIAVersion
        }
        catch
        {
            Write-Log `
                -Message "Unable to update failed marker: $($_.Exception.Message)" `
                -Level "ERROR"
        }


        if (-not $ForceRun)
        {
            Write-Log `
                -Message "Scheduled execution will retry on a later eligible logon." `
                -Level "WARNING"
        }


        Write-Log `
            -Message "$ScriptName failed." `
            -Level "ERROR"
    }
    else
    {
        Write-Host ""
        Write-Host "ERROR: $FailureReason" `
            -ForegroundColor Red
    }


    exit 1
}
finally
{
    if ($null -ne $ExecutionStopwatch)
    {
        if ($ExecutionStopwatch.IsRunning)
        {
            $ExecutionStopwatch.Stop()
        }

        $TotalDurationSeconds =
            [math]::Round(
                $ExecutionStopwatch.Elapsed.TotalSeconds,
                2
            )
    }
    else
    {
        $TotalDurationSeconds =
            $null
    }


    if ($LogFile)
    {
        $SummaryHPIAExitCode =
            if ($null -eq $HPIAExitCode) { "" } else { [string]$HPIAExitCode }

        $SummaryHPIADuration =
            if ($null -eq $HPIADurationSeconds) { "" } else { [string]$HPIADurationSeconds }

        Write-Log `
            -Message "SUMMARY|ExecutionId=$ExecutionId|ComponentVersion=$ComponentVersion|Outcome=$ExecutionOutcome|DetectedRecommendations=$DetectedRecommendationCount|ExcludedRecommendations=$ExcludedRecommendationCount|Recommendations=$RecommendationCount|TotalDurationSeconds=$TotalDurationSeconds|HPIADurationSeconds=$SummaryHPIADuration|HPIAExitCode=$SummaryHPIAExitCode"
    }


    if ($MutexAcquired)
    {
        try
        {
            $Mutex.ReleaseMutex()
        }
        catch
        {
        }
    }


    if ($Mutex)
    {
        $Mutex.Dispose()
    }
}
