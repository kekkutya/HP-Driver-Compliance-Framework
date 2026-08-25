# Hibaelhárítás

## Runtime

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

## Nincs új Evaluator log

Ez lehet teljesen normális. Disabled framework, nem eligible schedule vagy már meglévő aktuális success marker esetén az Evaluator szándékosan a logging/I/O előtt, minimális efforttal kilép.

Diagnosztikai teljes evaluation:

```powershell
C:\HPIA\Automation\DriverEvaluator.ps1 -ForceRun
```

## Snapshot

```powershell
Get-ChildItem "C:\HPIA\IAReport\Snapshots"
```

Teljes sikeres snapshot: egymáshoz tartozó `.manifest.json`, `.splist.txt`, `.success`. A 0 recommendation is valid; ilyenkor a Deployer `NoRecommendations` eredménnyel PSADT nélkül kilép.

## Deployer NoAction okok

Log:

```text
C:\HPIA\IAReport\DriverDeployer-<ComputerName>.log
```

Gyakori reasonök: `FrameworkDisabled`, `DriverDeployerDisabled`, `NoValidSnapshot`, `NoRecommendations`, `RingNotEligible`, `NoApplicableSoftPaqs`, `PSADTBusy`, `NoInternetConnection`, `DeploymentActive`.

## Deferred deployment

```text
HKLM\SOFTWARE\PSAppDeployToolkit\DeferHistory
```

Matching defer state esetén a Deployer ezt resume-olja az új snapshot előtt. Másik aktív PSADT mellett későbbre halasztja.

## Handoff

```text
C:\HPIA\IAReport\Deployment\Deployment.request.json
C:\HPIA\IAReport\Deployment\Deployment.splist.txt
C:\HPIA\IAReport\Deployment\Deployment.active
```

Matching defer state nélküli `Deployment.active` blokkolja az új Normal/ForceRun deploymentet; ezt nem célszerű vakon törölni.

## Ring

Ha a registryben nincs `BroadDelayDays`, a built-in default 21. Az effektív delay és a számított `Ring eligible at` időpont a Deployer logban látszik.

## HPIA exit code-ok

```text
0     success
256   nincs alkalmazható recommendation
1641  success; restart elindult
3010  success; restart szükséges
3020  egy vagy több SoftPaq install sikertelen
4098  nincs internetkapcsolat
4099  invalid SoftPaq number
```

## Store/MSIX PowerShell megjegyzés

A rekurzív HKLM registry törlés Microsoft Store/MSIX PowerShell 7.6.5 alatt `Requested registry access is not allowed` hibát adott, miközben Windows PowerShell 5.1 és MSI-s PowerShell 7.6.5 alatt ugyanaz a művelet működött. Hasonló registry-provider hiba esetén először ellenőrizd a tényleges `pwsh.exe` útvonalát.
