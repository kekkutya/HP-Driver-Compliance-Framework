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
    AppVersion = '__DRIVER_DEPLOYER_VERSION__'
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





$script:FinalExitCode = $null

# HP-DCF DriverDeployment contract.
$HPDCFDeploymentSPList = 'C:\HPIA\IAReport\Deployment\Deployment.splist.txt'
$HPDCFHPIAExe = 'C:\HPIA\HP Image Assistant\HPImageAssistant.exe'
$HPDCFHPIAReportFolder = 'C:\HPIA\IAReport'

function Set-HPDCFDeploymentCompletedState
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [int]$HPIAExitCode,

        [string]$DeploymentRequestFile = 'C:\HPIA\IAReport\Deployment\Deployment.request.json',

        [string]$SnapshotFolder = 'C:\HPIA\IAReport\Snapshots'
    )

    if (-not (Test-Path -LiteralPath $DeploymentRequestFile -PathType Leaf))
    {
        return
    }

    $DeploymentRequest =
        Get-Content -LiteralPath $DeploymentRequestFile -Raw -ErrorAction Stop |
        ConvertFrom-Json -ErrorAction Stop

    $SnapshotExecutionId =
        [string]$DeploymentRequest.SnapshotExecutionId

    if ([string]::IsNullOrWhiteSpace($SnapshotExecutionId))
    {
        return
    }

    $SnapshotManifest = Get-ChildItem `
        -LiteralPath $SnapshotFolder `
        -Filter '*.manifest.json' `
        -File `
        -ErrorAction Stop |
        Where-Object {
            try
            {
                $Manifest =
                    Get-Content -LiteralPath $_.FullName -Raw -ErrorAction Stop |
                    ConvertFrom-Json -ErrorAction Stop

                [string]$Manifest.ExecutionId -eq $SnapshotExecutionId
            }
            catch
            {
                $false
            }
        } |
        Select-Object -First 1

    if ($null -eq $SnapshotManifest)
    {
        throw "Unable to resolve source snapshot for deployment execution ID [$SnapshotExecutionId]."
    }

    $DeployedMarker =
        $SnapshotManifest.FullName -replace '\.manifest\.json$', '.deployed'

    $DeployedMarkerContent = @(
        "SnapshotExecutionId=$SnapshotExecutionId"
        "DeployedAt=$((Get-Date).ToString('o'))"
        "HPIAExitCode=$HPIAExitCode"
    )

    $DeployedMarkerTemp = "$DeployedMarker.tmp"

    $DeployedMarkerContent |
        Set-Content `
            -LiteralPath $DeployedMarkerTemp `
            -Encoding UTF8 `
            -ErrorAction Stop

    Move-Item `
        -LiteralPath $DeployedMarkerTemp `
        -Destination $DeployedMarker `
        -Force `
        -ErrorAction Stop

    Write-ADTLogEntry -Message "Deployment completion marker created: [$DeployedMarker]"
}


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
    ## Persist successful deployment completion for the source snapshot before
    ## removing the transient deployment handoff state.
    Set-HPDCFDeploymentCompletedState -HPIAExitCode $HPIAExitCode

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
            -Message (Get-ADTStringTable).BalloonTip.Complete.Install `
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

