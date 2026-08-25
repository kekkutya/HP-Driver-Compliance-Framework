<#

.SYNOPSIS
PSAppDeployToolkit - This script performs the installation or uninstallation of an application(s).

.DESCRIPTION
- The script is provided as a template to perform an install, uninstall, or repair of an application(s).
- The script either performs an "Install", "Uninstall", or "Repair" deployment type.
- The install deployment type is broken down into 3 main sections/phases: Pre-Install, Install, and Post-Install.

The script imports the PSAppDeployToolkit module which contains the logic and functions required to install or uninstall an application.

.PARAMETER DeploymentType
The type of deployment to perform.

.PARAMETER DeployMode
Specifies whether the installation should be run in Interactive (shows dialogs), Silent (no dialogs), NonInteractive (dialogs without prompts) mode, or Auto (shows dialogs if a user is logged on, device is not in the OOBE, and there's no running apps to close).

Silent mode is automatically set if it is detected that the process is not user interactive, no users are logged on, the device is in Autopilot mode, or there's specified processes to close that are currently running.

.PARAMETER SuppressRebootPassThru
Suppresses the 3010 return code (requires restart) from being passed back to the parent process (e.g. SCCM) if detected from an installation. If 3010 is passed back to SCCM, a reboot prompt will be triggered.

.PARAMETER TerminalServerMode
Changes to "user install mode" and back to "user execute mode" for installing/uninstalling applications for Remote Desktop Session Hosts/Citrix servers.

.PARAMETER DisableLogging
Disables logging to file for the script.

.EXAMPLE
powershell.exe -File Invoke-AppDeployToolkit.ps1

.EXAMPLE
powershell.exe -File Invoke-AppDeployToolkit.ps1 -DeployMode Silent

.EXAMPLE
powershell.exe -File Invoke-AppDeployToolkit.ps1 -DeploymentType Uninstall

.EXAMPLE
Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent

.INPUTS
None. You cannot pipe objects to this script.

.OUTPUTS
None. This script does not generate any output.

.NOTES
Toolkit Exit Code Ranges:
- 60000 - 68999: Reserved for built-in exit codes in Invoke-AppDeployToolkit.ps1, and Invoke-AppDeployToolkit.exe
- 69000 - 69999: Recommended for user customized exit codes in Invoke-AppDeployToolkit.ps1
- 70000 - 79999: Recommended for user customized exit codes in PSAppDeployToolkit.Extensions module.

.LINK
https://psappdeploytoolkit.com

#>

[CmdletBinding()]
param
(
    # Default is 'Install'.
    [Parameter(Mandatory = $false)]
    [ValidateSet('Install', 'Uninstall', 'Repair')]
    [System.String]$DeploymentType,

    # Default is 'Auto'. Don't hard-code this unless required.
    [Parameter(Mandatory = $false)]
    [ValidateSet('Auto', 'Interactive', 'NonInteractive', 'Silent')]
    [System.String]$DeployMode,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$SuppressRebootPassThru,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$TerminalServerMode,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$DisableLogging
)


##================================================
## MARK: Variables
##================================================

# Zero-Config MSI support is provided when "AppName" is null or empty.
# By setting the "AppName" property, Zero-Config MSI will be disabled.
$adtSession = @{
    # App variables.
    AppVendor = 'HP'
    AppName = 'DCF DriverDeployer'
    AppVersion = '1.0.0'
    AppArch = 'x86'
    AppLang = 'EN'
    AppRevision = '01'
    AppSuccessExitCodes = @(0, 256)
    AppRebootExitCodes = @(1641, 3010)
    AppProcessesToClose = @()  # Example: @('excel', @{ Name = 'winword'; Description = 'Microsoft Word' })
    AppScriptVersion = '1.0.0'
    AppScriptDate = '2026-08-22'
    AppScriptAuthor = 'Zoltan Elias'
    RequireAdmin = $true

    # Install Titles (Only set here to override defaults set by the toolkit).
    InstallName = ''
    InstallTitle = ''

    # Script variables.
    DeployAppScriptFriendlyName = $MyInvocation.MyCommand.Name
    DeployAppScriptParameters = $PSBoundParameters
    DeployAppScriptVersion = '4.1.8'
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
    param
    (
    )

    $DownloadPath = 'C:\HPIA'
    $InstallPath = 'C:\HPIA\HP Image Assistant'
    $HPIAExe = Join-Path -Path $InstallPath -ChildPath 'HPImageAssistant.exe'
    $DownloadedSoftpaq = $null

    try
    {
        Write-ADTLogEntry -Message 'Starting HP Image Assistant version check.'

        $UpdateInfo = Get-HPImageAssistantUpdateInfo -ErrorAction Stop
        $LatestVersion = $UpdateInfo.Version.ToString()

        if ([string]::IsNullOrWhiteSpace($LatestVersion))
        {
            throw 'Get-HPImageAssistantUpdateInfo did not return a Version.'
        }

        $LatestBaseVersion = Get-HPIABaseVersion -VersionString $LatestVersion
        Write-ADTLogEntry -Message "Latest HP Image Assistant version: $LatestVersion"

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
            Write-ADTLogEntry -Message "Installed HP Image Assistnt version: $InstalledVersion"

            if ($InstalledBaseVersion -eq $LatestBaseVersion)
            {
                Write-ADTLogEntry -Message 'HP Image Assistant is already up to date.'
                Write-ADTLogEntry -Message "HP Image Assistant executable path: $HPIAExe"
                $InstallRequired = $false
            }
            else
            {
                Write-ADTLogEntry -Message "HP Image Assistant update required. Installed release: $InstalledBaseVersion; latest release: $LatestBaseVersion"
            }
        }
        else
        {
            Write-ADTLogEntry -Message 'HP Image Assistant is not installed.'
        }

        if (-not $InstallRequired)
        {
            return
        }

        if (-not (Test-Path -Path $DownloadPath -PathType Container))
        {
            New-Item -Path $DownloadPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-ADTLogEntry -Message "Created HP Image Assistant download folder: $DownloadPath"
        }

        if (-not (Test-Path -Path $InstallPath -PathType Container))
        {
            New-Item -Path $InstallPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-ADTLogEntry -Message "Created HP Image Assistant installation folder: $InstallPath"
        }

        $StaleSoftpaqs = Get-ChildItem -Path $DownloadPath -Filter 'hp-hpia-*.exe' -File -ErrorAction SilentlyContinue
        foreach ($StaleSoftpaq in $StaleSoftpaqs)
        {
            Write-ADTLogEntry -Message "Removing stale HP Image Assistant SoftPaq: $($StaleSoftpaq.FullName)"
            Remove-Item -Path $StaleSoftpaq.FullName -Force -ErrorAction Stop
        }

        Write-ADTLogEntry -Message "Downloading HP Image Assistant $LatestVersion to: $DownloadPath"

        $DownloadParams = @{
            DestinationPath = $DownloadPath
            ErrorAction = 'Stop'
        }

        $DownloadOutput = Install-HPImageAssistant @DownloadParams 2>&1
        foreach ($OutputLine in $DownloadOutput)
        {
            if ($null -ne $OutputLine -and -not [string]::IsNullOrWhiteSpace($OutputLine.ToString()))
            {
                Write-ADTLogEntry -Message "Install-HPImageAssistant: $($OutputLine.ToString())"
            }
        }

        $ExpectedSoftpaq = Join-Path -Path $DownloadPath -ChildPath "hp-hpia-$LatestVersion.exe"
        if (Test-Path -Path $ExpectedSoftpaq -PathType Leaf)
        {
            $DownloadedSoftpaq = Get-Item -Path $ExpectedSoftpaq -ErrorAction Stop
        }
        else
        {
            $DownloadedSoftpaq = Get-ChildItem -Path $DownloadPath -Filter 'hp-hpia-*.exe' -File -ErrorAction SilentlyContinue | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1
        }

        if ($null -eq $DownloadedSoftpaq)
        {
            throw "Downloaded HP Image Assistant SoftPaq was not found in: $DownloadPath"
        }

        Write-ADTLogEntry -Message "Downloaded HP Image Assistant SoftPaq: $($DownloadedSoftpaq.FullName)"

        $OldFiles = Get-ChildItem -Path $InstallPath -Force -ErrorAction SilentlyContinue
        if ($OldFiles)
        {
            Write-ADTLogEntry -Message "Removing old extracted HP Image Assistant files from: $InstallPath"
            $OldFiles | Remove-Item -Recurse -Force -ErrorAction Stop
        }

        Write-ADTLogEntry -Message "Extracting HP Image Assistant to: $InstallPath"

        $ExtractArgumentString = '/s /e /f "{0}"' -f $InstallPath
        Write-ADTLogEntry -Message "Running extractor: $($DownloadedSoftpaq.FullName) $ExtractArgumentString"

        $ExtractProcess = Start-Process -FilePath $DownloadedSoftpaq.FullName -ArgumentList $ExtractArgumentString -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
        Write-ADTLogEntry -Message "HP Image Assistant extractor exit code: $($ExtractProcess.ExitCode)"

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
        Write-ADTLogEntry -Message "Installed HP Image Assistant version after extraction: $InstalledVersion"

        if ($InstalledBaseVersion -ne $LatestBaseVersion)
        {
            throw "Installed version ($InstalledVersion) does not match expected release ($LatestVersion)."
        }

        if (Test-Path -Path $DownloadedSoftpaq.FullName -PathType Leaf)
        {
            Write-ADTLogEntry -Message "Removing downloaded HP Image Assistant SoftPaq: $($DownloadedSoftpaq.FullName)"
            Remove-Item -Path $DownloadedSoftpaq.FullName -Force -ErrorAction Stop
            Write-ADTLogEntry -Message 'Downloaded HP Image Assistant SoftPaq removed successfully.'
        }

        Write-ADTLogEntry -Message 'HP Image Assistant successfully installed/updated.'
        Write-ADTLogEntry -Message "HP Image Assistant version: $InstalledVersion"
        Write-ADTLogEntry -Message "HP Image Assistant executable path: $HPIAExe"
    }
    catch
    {
        Write-ADTLogEntry -Message "HP Image Assistant installation/update failed: $($_.Exception.Message)" -Severity 3
        throw
    }
}

$script:FinalExitCode = $null

# HP-DCF DriverDeployment contract.
$HPDCFDeploymentSPList = 'C:\HPIA\IAReport\Deployment\Deployment.splist.txt'
$HPDCFHPIAExe = 'C:\HPIA\HP Image Assistant\HPImageAssistant.exe'
$HPDCFHPIAReportFolder = 'C:\HPIA\IAReport'

function Install-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )

    ##================================================
    ## MARK: Pre-Install
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    ## Show Welcome Message, close processes if specified, allow up to 3 deferrals, verify there is enough disk space to complete the install, and persist the prompt.
    $saiwParams = @{
        AllowDefer = $true
        DeferTimes = 3
        CheckDiskSpace = $true
        PersistPrompt = $true
    }
    if ($adtSession.AppProcessesToClose.Count -gt 0)
    {
        $saiwParams.Add('CloseProcesses', $adtSession.AppProcessesToClose)
    }
    Show-ADTInstallationWelcome @saiwParams

    ## Show Progress Message (with the default message).
    Show-ADTInstallationProgress

    ## <Perform Pre-Installation tasks here>


    ##================================================
    ## MARK: Install
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    ## Handle Zero-Config MSI installations.
    if ($adtSession.UseDefaultMsi)
    {
        $ExecuteDefaultMSISplat = @{ Action = $adtSession.DeploymentType; FilePath = $adtSession.DefaultMsiFile }
        if ($adtSession.DefaultMstFile)
        {
            $ExecuteDefaultMSISplat.Add('Transforms', $adtSession.DefaultMstFile)
        }
        Start-ADTMsiProcess @ExecuteDefaultMSISplat
        if ($adtSession.DefaultMspFiles)
        {
            $adtSession.DefaultMspFiles | Start-ADTMsiProcess -Action Patch
        }
    }

    ## Execute the frozen HP-DCF deployment payload.
    $HPIAArguments = @(
        '/Operation:Analyze'
        '/Action:Install'
        "/SPList:`"$HPDCFDeploymentSPList`""
        '/AutoCleanup'
        '/Noninteractive'
        '/Debug'
        "/ReportFolder:`"$HPDCFHPIAReportFolder`""
    ) -join ' '

    # HPIA codes 3020, 4098 and 4099 are intentionally passed through the
    # PSADT process wrapper so DriverDeployment can classify and log them.
    # Reboot codes remain on PSADT's native reboot path.
    $HPIAHandledExitCodes = @(0, 256, 3020, 4098, 4099)
    $HPIARebootExitCodes = @($adtSession.AppRebootExitCodes)

    Write-ADTLogEntry -Message "Starting HP Image Assistant deployment from SPList: [$HPDCFDeploymentSPList]"
    Write-ADTLogEntry -Message "HP Image Assistant arguments: [$HPIAArguments]"
    Write-ADTLogEntry -Message "HPIA handled exit codes: [$($HPIAHandledExitCodes -join ', ')]"
    Write-ADTLogEntry -Message "HPIA reboot exit codes: [$($HPIARebootExitCodes -join ', ')]"

    $HPIAResult = Start-ADTProcess `
        -FilePath $HPDCFHPIAExe `
        -ArgumentList $HPIAArguments `
        -SuccessExitCodes $HPIAHandledExitCodes `
        -RebootExitCodes $HPIARebootExitCodes `
        -PassThru

    $HPIAExitCode = [int]$HPIAResult.ExitCode
    Write-ADTLogEntry -Message "HP Image Assistant finished with exit code [$HPIAExitCode]."

    switch ($HPIAExitCode)
    {
        0 { Write-ADTLogEntry -Message 'HP Image Assistant deployment completed successfully.' }
        256 { Write-ADTLogEntry -Message 'HP Image Assistant completed with no applicable recommendations.' }
        1641 { Write-ADTLogEntry -Message 'HP Image Assistant completed successfully and initiated a restart.' }
        3010 { Write-ADTLogEntry -Message 'HP Image Assistant completed successfully and requires a restart.' }
        3020 { throw 'HP Image Assistant deployment failed: one or more SoftPaq installations failed. Exit code [3020].' }
        4098 { throw 'HP Image Assistant deployment failed: no internet connection. Exit code [4098].' }
        4099 { throw 'HP Image Assistant deployment failed: invalid SoftPaq number in SPList. Exit code [4099].' }
        default { throw "HP Image Assistant deployment failed with exit code [$HPIAExitCode]." }
    }



    ##================================================
    ## MARK: Post-Install
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## <Perform Post-Installation tasks here>

    ## HPIA reached a successful or reboot-required final state.
    ## Remove the completed HP-DCF deployment handoff state.
    $HPDCFDeploymentStateFiles = @(
        'C:\HPIA\IAReport\Deployment\Deployment.active',
        'C:\HPIA\IAReport\Deployment\Deployment.request.json',
        'C:\HPIA\IAReport\Deployment\Deployment.splist.txt'
    )

    foreach ($StateFile in $HPDCFDeploymentStateFiles)
    {
        if (Test-Path -LiteralPath $StateFile -PathType Leaf)
        {
            Write-ADTLogEntry -Message "Removing completed HP-DCF deployment state: [$StateFile]"
            Remove-Item -LiteralPath $StateFile -Force -ErrorAction Stop
        }
    }

    Write-ADTLogEntry -Message 'HP-DCF deployment handoff completed successfully.'

    if ($HPIAExitCode -in $HPIARebootExitCodes)
    {
        Write-ADTLogEntry -Message "Preserving HPIA reboot exit code [$HPIAExitCode] for PSADT session completion."
        $script:FinalExitCode = $HPIAExitCode
    }



    ## Display the appropriate completion prompt.
    if ($HPIAExitCode -in $HPIARebootExitCodes)
    {
        Write-ADTLogEntry -Message "Displaying restart prompt for HPIA exit code [$HPIAExitCode]."
        Show-ADTInstallationRestartPrompt `
            -CountdownSeconds 300 `
            -CountdownNoHideSeconds 300
    }
    elseif (!$adtSession.UseDefaultMsi)
    {
        Show-ADTInstallationPrompt `
            -Message 'A HP eszközmeghajtók frissítése sikeresen befejeződött.' `
            -ButtonRightText 'OK'
    }
}

function Uninstall-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )

    ##================================================
    ## MARK: Pre-Uninstall
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    ## If there are processes to close, show Welcome Message with a 60 second countdown before automatically closing.
    if ($adtSession.AppProcessesToClose.Count -gt 0)
    {
        Show-ADTInstallationWelcome -CloseProcesses $adtSession.AppProcessesToClose -CloseProcessesCountdown 60
    }

    ## Show Progress Message (with the default message).
    Show-ADTInstallationProgress

    ## <Perform Pre-Uninstallation tasks here>


    ##================================================
    ## MARK: Uninstall
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    ## Handle Zero-Config MSI uninstallations.
    if ($adtSession.UseDefaultMsi)
    {
        $ExecuteDefaultMSISplat = @{ Action = $adtSession.DeploymentType; FilePath = $adtSession.DefaultMsiFile }
        if ($adtSession.DefaultMstFile)
        {
            $ExecuteDefaultMSISplat.Add('Transforms', $adtSession.DefaultMstFile)
        }
        Start-ADTMsiProcess @ExecuteDefaultMSISplat
    }

    ## <Perform Uninstallation tasks here>


    ##================================================
    ## MARK: Post-Uninstallation
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## <Perform Post-Uninstallation tasks here>
}

function Repair-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )

    ##================================================
    ## MARK: Pre-Repair
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    ## If there are processes to close, show Welcome Message with a 60 second countdown before automatically closing.
    if ($adtSession.AppProcessesToClose.Count -gt 0)
    {
        Show-ADTInstallationWelcome -CloseProcesses $adtSession.AppProcessesToClose -CloseProcessesCountdown 60
    }

    ## Show Progress Message (with the default message).
    Show-ADTInstallationProgress

    ## <Perform Pre-Repair tasks here>


    ##================================================
    ## MARK: Repair
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    ## Handle Zero-Config MSI repairs.
    if ($adtSession.UseDefaultMsi)
    {
        $ExecuteDefaultMSISplat = @{ Action = $adtSession.DeploymentType; FilePath = $adtSession.DefaultMsiFile }
        if ($adtSession.DefaultMstFile)
        {
            $ExecuteDefaultMSISplat.Add('Transforms', $adtSession.DefaultMstFile)
        }
        Start-ADTMsiProcess @ExecuteDefaultMSISplat
    }

    ## <Perform Repair tasks here>


    ##================================================
    ## MARK: Post-Repair
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## <Perform Post-Repair tasks here>
}


##================================================
## MARK: Initialization
##================================================

# Set strict error handling across entire operation.
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
Set-StrictMode -Version 1

# Import the module and instantiate a new session.
try
{
    # Import the module locally if available, otherwise try to find it from PSModulePath.
    if (Test-Path -LiteralPath "$PSScriptRoot\PSAppDeployToolkit\PSAppDeployToolkit.psd1" -PathType Leaf)
    {
        Get-ChildItem -LiteralPath "$PSScriptRoot\PSAppDeployToolkit" -Recurse -File | Unblock-File -ErrorAction Ignore
        Import-Module -FullyQualifiedName @{ ModuleName = "$PSScriptRoot\PSAppDeployToolkit\PSAppDeployToolkit.psd1"; Guid = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.1.8' } -Force
    }
    else
    {
        Import-Module -FullyQualifiedName @{ ModuleName = 'PSAppDeployToolkit'; Guid = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.1.8' } -Force
    }

    # Open a new deployment session, replacing $adtSession with a DeploymentSession.
    $iadtParams = Get-ADTBoundParametersAndDefaultValues -Invocation $MyInvocation
    $adtSession = Remove-ADTHashtableNullOrEmptyValues -Hashtable $adtSession
    $adtSession = Open-ADTSession @adtSession @iadtParams -PassThru
}
catch
{
    $Host.UI.WriteErrorLine((Out-String -InputObject $_ -Width ([System.Int32]::MaxValue)))
    exit 60008
}


##================================================
## MARK: Invocation
##================================================

# Commence the actual deployment operation.
try
{
    # Import any found extensions before proceeding with the deployment.
    Get-ChildItem -LiteralPath $PSScriptRoot -Directory | & {
        process
        {
            if ($_.Name -match 'PSAppDeployToolkit\..+$')
            {
                Get-ChildItem -LiteralPath $_.FullName -Recurse -File | Unblock-File -ErrorAction Ignore
                Import-Module -Name $_.FullName -Force
            }
        }
    }

    # Invoke the deployment and close out the session.
    & "$($adtSession.DeploymentType)-ADTDeployment"

    if ($null -ne $script:FinalExitCode)
    {
        Close-ADTSession -ExitCode $script:FinalExitCode
    }
    else
    {
        Close-ADTSession
    }
}
catch
{
    # An unhandled error has been caught.
    $mainErrorMessage = "An unhandled error within [$($MyInvocation.MyCommand.Name)] has occurred.`n$(Resolve-ADTErrorRecord -ErrorRecord $_)"
    Write-ADTLogEntry -Message $mainErrorMessage -Severity 3

    ## Error details hidden from the user by default. Show a simple dialog with full stack trace:
    # Show-ADTDialogBox -Text $mainErrorMessage -Icon Stop -NoWait

    ## Or, a themed dialog with basic error message:
    # Show-ADTInstallationPrompt -Message "$($adtSession.DeploymentType) failed at line $($_.InvocationInfo.ScriptLineNumber), char $($_.InvocationInfo.OffsetInLine):`n$($_.InvocationInfo.Line.Trim())`n`nMessage:`n$($_.Exception.Message)" -ButtonRightText OK -Icon Error -NoWait

    Close-ADTSession -ExitCode 60001
}

