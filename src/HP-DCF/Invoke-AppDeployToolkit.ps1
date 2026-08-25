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
    AppName = 'Driver Compliance Framework'
    AppVersion = '1.0.0'
    AppArch = 'x86'
    AppLang = 'EN'
    AppRevision = '01'
    AppSuccessExitCodes = @(0)
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

function Register-HPDCFFrameworkTask
{
    [CmdletBinding()]
    param
    (
    )

    $TaskName = 'HP Driver Compliance Framework'
    $EvaluatorScript = 'C:\HPIA\Automation\DriverEvaluator.ps1'
    $DeployerScript = 'C:\HPIA\Automation\DriverDeployer.ps1'

    foreach ($RequiredScript in @($EvaluatorScript, $DeployerScript))
    {
        if (-not (Test-Path -LiteralPath $RequiredScript -PathType Leaf))
        {
            throw "Scheduled task source script was not found: $RequiredScript"
        }
    }

    Write-ADTLogEntry -Message "Registering scheduled task: [$TaskName]."

    $EvaluatorAction = New-ScheduledTaskAction `
        -Execute 'powershell.exe' `
        -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $EvaluatorScript)

    $DeployerAction = New-ScheduledTaskAction `
        -Execute 'powershell.exe' `
        -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $DeployerScript)

    $Trigger = New-ScheduledTaskTrigger -AtLogOn
    $Trigger.Delay = 'PT3M'

    $Principal = New-ScheduledTaskPrincipal `
        -UserId 'SYSTEM' `
        -LogonType ServiceAccount `
        -RunLevel Highest

    $Settings = New-ScheduledTaskSettingsSet `
        -MultipleInstances IgnoreNew `
        -StartWhenAvailable `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries

    $Task = New-ScheduledTask `
        -Action @($EvaluatorAction, $DeployerAction) `
        -Trigger $Trigger `
        -Principal $Principal `
        -Settings $Settings `
        -Description 'HP Driver Compliance Framework - Runs DriverEvaluator followed by DriverDeployer after user logon.'

    Register-ScheduledTask `
        -TaskName $TaskName `
        -InputObject $Task `
        -Force `
        -ErrorAction Stop | Out-Null

    $RegisteredTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop

    if ($RegisteredTask.Actions.Count -ne 2)
    {
        throw "Scheduled task [$TaskName] was registered with an unexpected action count: $($RegisteredTask.Actions.Count)"
    }

    Write-ADTLogEntry -Message "Scheduled task registered successfully: [$TaskName]. Trigger: any user logon + 3 minutes. Actions: DriverEvaluator -> DriverDeployer. Principal: SYSTEM/Highest."
}

function Unregister-HPDCFFrameworkTask
{
    [CmdletBinding()]
    param
    (
    )

    $TaskName = 'HP Driver Compliance Framework'
    $ExistingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

    if ($null -eq $ExistingTask)
    {
        Write-ADTLogEntry -Message "Scheduled task does not exist. Nothing to remove: [$TaskName]."
        return
    }

    Write-ADTLogEntry -Message "Removing scheduled task: [$TaskName]."
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
    Write-ADTLogEntry -Message "Scheduled task removed successfully: [$TaskName]."
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
        AllowDefer = $false
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

    ## <Perform Installation tasks here>
    Install-ADTWinGetPackage -Id HP.HPCMSL -Force
    Invoke-HPIAInstallOrUpdate


    ##================================================
    ## MARK: Post-Install
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## <Perform Post-Installation tasks here>
    # Copy tools to local folder
    $DestinationPath = "C:\HPIA"
    Write-ADTLogEntry -Message "Copying folders from SupportFiles to [$DestinationPath]. Root files will be skipped."
    if (-not (Test-Path -Path $DestinationPath -PathType Container))
    {
        New-ADTFolder -Path $DestinationPath
        Write-ADTLogEntry -Message "Created destination folder: [$DestinationPath]."
    }
    $SupportFolders = Get-ChildItem -Path $adtSession.DirSupportFiles -Directory -ErrorAction Stop
    foreach ($Folder in $SupportFolders)
    {
        Write-ADTLogEntry -Message "Copying folder [$($Folder.Name)] to [$DestinationPath]."
        Copy-ADTFile -Path $Folder.FullName -Destination $DestinationPath -Recurse
        Write-ADTLogEntry -Message "Folder [$($Folder.Name)] copied successfully."
    }

    # Register or refresh the framework orchestration task after the automation payload is in place.
    Register-HPDCFFrameworkTask

    ## Display a message at the end of the install.
    if (!$adtSession.UseDefaultMsi)
    {

    }

    ## Intune detection key
    Set-ADTRegistryKey -Key "HKLM\SOFTWARE\InstalledApps\HPDriverComplianceFramework"
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
    # Remove the orchestration task before uninstalling framework files.
    Unregister-HPDCFFrameworkTask


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
    Uninstall-ADTWinGetPackage -Id HP.HPCMSL


    ##================================================
    ## MARK: Post-Uninstallation
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## <Perform Post-Uninstallation tasks here>
    # Remove folders
    $HPIARootPath = "C:\HPIA"
    if (Test-Path -Path $HPIARootPath -PathType Container)
    {
        Write-ADTLogEntry -Message "Removing HPIA folder: $HPIARootPath"
        Remove-ADTFolder -Path $HPIARootPath
        if (Test-Path -Path $HPIARootPath -PathType Container)
        {
            Write-ADTLogEntry -Message "Failed to remove HPIA folder: $HPIARootPath" -Severity 3
            throw "HPIA folder still exists after removal attempt: $HPIARootPath"
        }
    
        Write-ADTLogEntry -Message "HPIA folder removed successfully: $HPIARootPath"
    }
    else
    {
        Write-ADTLogEntry -Message "HPIA folder does not exist. Nothing to remove: $HPIARootPath"
    }
    
    ## Remove HP-DCF framework configuration.
    $FrameworkRegistryPath = 'HKLM\SOFTWARE\HPDriverComplianceFramework'

    Write-ADTLogEntry -Message "Removing HP-DCF framework registry configuration: [$FrameworkRegistryPath]"
    Remove-ADTRegistryKey `
        -Key $FrameworkRegistryPath `
        -Recurse

    if (Test-Path -LiteralPath "Registry::$FrameworkRegistryPath")
    {
        throw "HP-DCF framework registry configuration still exists after removal: [$FrameworkRegistryPath]"
    }

    Write-ADTLogEntry -Message 'HP-DCF framework registry configuration removed successfully.'
    
    ## Intune detection key
    Remove-ADTRegistryKey -Key "HKLM\SOFTWARE\InstalledApps\HPDriverComplianceFramework"
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
    Install-ADTWinGetPackage -Id HP.HPCMSL -Force
    Invoke-HPIAInstallOrUpdate


    ##================================================
    ## MARK: Post-Repair
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## <Perform Post-Repair tasks here>
    # Copy tools to local folder
    $DestinationPath = "C:\HPIA"
    Write-ADTLogEntry -Message "Copying folders from SupportFiles to [$DestinationPath]. Root files will be skipped."
    if (-not (Test-Path -Path $DestinationPath -PathType Container))
    {
        New-ADTFolder -Path $DestinationPath
        Write-ADTLogEntry -Message "Created destination folder: [$DestinationPath]."
    }
    $SupportFolders = Get-ChildItem -Path $adtSession.DirSupportFiles -Directory -ErrorAction Stop
    foreach ($Folder in $SupportFolders)
    {
        Write-ADTLogEntry -Message "Copying folder [$($Folder.Name)] to [$DestinationPath]."
        Copy-ADTFile -Path $Folder.FullName -Destination $DestinationPath -Recurse
        Write-ADTLogEntry -Message "Folder [$($Folder.Name)] copied successfully."
    }

    # Register or refresh the framework orchestration task after the automation payload is in place.
    Register-HPDCFFrameworkTask

    ## Display a message at the end of the install.
    if (!$adtSession.UseDefaultMsi)
    {

    }

    ## Intune detection key
    Set-ADTRegistryKey -Key "HKLM\SOFTWARE\InstalledApps\HPDriverComplianceFramework"
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
    Close-ADTSession
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

