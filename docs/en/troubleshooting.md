# Troubleshooting

## Runtime checks

```powershell
Test-Path "C:\HPIA\Automation\DriverEvaluator.ps1"
Test-Path "C:\HPIA\Automation\DriverDeployer.ps1"
Test-Path "C:\HPIA\HP Image Assistant\HPImageAssistant.exe"
Test-Path "C:\HPIA\DriverDeployment\Invoke-AppDeployToolkit.exe"
```

## Scheduled Task

```powershell
Get-ScheduledTask -TaskName "HP Driver Compliance Framework"
Get-ScheduledTaskInfo -TaskName "HP Driver Compliance Framework"
```

Expected actions are DriverEvaluator followed by DriverDeployer. The task normally runs as SYSTEM with highest privileges.

## Evaluator has no new log

This can be expected. DriverEvaluator deliberately exits before normal logging/I/O when the framework is disabled, the schedule is not eligible, or the current occurrence already has a success marker.

For a forced diagnostic evaluation:

```powershell
C:\HPIA\Automation\DriverEvaluator.ps1 -ForceRun
```

## Snapshot checks

```powershell
Get-ChildItem "C:\HPIA\IAReport\Snapshots"
```

A successful complete snapshot has matching:

```text
Evaluation-<period>.manifest.json
Evaluation-<period>.splist.txt
Evaluation-<period>.success
```

A zero-recommendation snapshot is valid; DriverDeployer will report `NoRecommendations` and will not start PSADT.

## Deployer no-action reasons

Review:

```text
C:\HPIA\IAReport\DriverDeployer-<ComputerName>.log
```

Common `Reason` values include `FrameworkDisabled`, `DriverDeployerDisabled`, `NoValidSnapshot`, `NoRecommendations`, `RingNotEligible`, `NoApplicableSoftPaqs`, `PSADTBusy`, `NoInternetConnection`, `DeploymentActive`, and `DeferredResume` for a resumed deployment start.

## Deferred deployment

Check the DriverDeployment PSADT defer namespace:

```text
HKLM\SOFTWARE\PSAppDeployToolkit\DeferHistory
```

When matching defer state exists, DriverDeployer resumes it before selecting a new snapshot. If another PSADT process is active, resume is deferred to a later framework execution.

## Deployment handoff

```powershell
Get-ChildItem "C:\HPIA\IAReport\Deployment" -ErrorAction SilentlyContinue
```

Relevant files:

```text
Deployment.request.json
Deployment.splist.txt
Deployment.active
```

`Deployment.active` without matching defer state blocks a new Normal/ForceRun deployment and should be investigated rather than deleted blindly.

## Exclusions

```powershell
Get-ItemProperty "HKLM:\SOFTWARE\HPDriverComplianceFramework" |
    Select-Object Enabled, ExcludeSoftPaqs
```

The exclusion list is re-checked immediately before Normal/ForceRun handoff.

## Ring eligibility

```powershell
Get-ItemProperty "HKLM:\SOFTWARE\HPDriverComplianceFramework\DriverDeployer" |
    Select-Object Enabled, Ring, BroadDelayDays
```

If `BroadDelayDays` is absent, the built-in default is 21. The effective value and calculated `Ring eligible at` timestamp are written to the DriverDeployer log.

## HPIA / deployment exit codes

The current deployment paths explicitly handle:

```text
0     success
256   no applicable recommendations
1641  success; restart initiated
3010  success; restart required
3020  one or more SoftPaq installations failed
4098  no internet connection
4099  invalid SoftPaq number
```

## Store/MSIX PowerShell note

Recursive HKLM registry deletion may fail under Microsoft Store/MSIX PowerShell 7.6.5 with `Requested registry access is not allowed`, while the same operation succeeded under Windows PowerShell 5.1 and MSI-installed PowerShell 7.6.5. If reproducing registry-provider access anomalies, confirm the actual `pwsh.exe` path and compare against the MSI build before changing HP-DCF ACLs.
