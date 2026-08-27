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

## Nincs új Evaluator-napló

Ez lehet teljesen normális. Letiltott framework, nem jogosult ütemezés vagy már meglévő aktuális `.success` jelzőfájl esetén az Evaluator szándékosan a naplózási és egyéb I/O-műveletek előtt, minimális erőforrás-ráfordítással kilép.

Teljes diagnosztikai kiértékelés:

```powershell
C:\HPIA\Automation\DriverEvaluator.ps1 -ForceRun
```

## Snapshot

```powershell
Get-ChildItem "C:\HPIA\IAReport\Snapshots"
```

Teljes sikeres snapshot: egymáshoz tartozó `.manifest.json`, `.splist.txt` és `.success` fájl. A 0 ajánlást tartalmazó snapshot is érvényes; ilyenkor a Deployer `NoRecommendations` eredménnyel, PSADT indítása nélkül kilép. Az egyező `Evaluation-<period>.deployed` marker azt rögzíti, hogy a snapshot már sikeres vagy újraindítást igénylő telepítési végállapotot ért el; a későbbi Normal futások `AlreadyDeployed` eredménnyel, PSADT indítása nélkül lépnek ki.

## A Deployer NoAction eredményének okai

Napló:

```text
C:\HPIA\IAReport\DriverDeployer-<ComputerName>.log
```

Gyakori okok: `FrameworkDisabled`, `DriverDeployerDisabled`, `NoValidSnapshot`, `NoRecommendations`, `AlreadyDeployed`, `RingNotEligible`, `NoApplicableSoftPaqs`, `PSADTBusy`, `NoInternetConnection`, `DeploymentActive`.

## Elhalasztott telepítés

```text
HKLM\SOFTWARE\PSAppDeployToolkit\DeferHistory
```

A DriverDeploymenthez tartozó elhalasztási állapot esetén a Deployer először ellenőrzi a megőrzött átadáshoz tartozó snapshotot. Ha ehhez már egyező `.deployed` marker tartozik, az elavult defer- és átadási állapot `AlreadyDeployed` eredménnyel törlődik. Egyébként az elhalasztott telepítés folytatása elsőbbséget élvez az új snapshot feldolgozásával szemben. Másik aktív PSADT mellett a folytatást későbbre halasztja.

## Telepítési átadás

```text
C:\HPIA\IAReport\Deployment\Deployment.request.json
C:\HPIA\IAReport\Deployment\Deployment.splist.txt
C:\HPIA\IAReport\Deployment\Deployment.active
```

A DriverDeploymenthez tartozó elhalasztási állapot nélküli `Deployment.active` blokkolja az új Normal/ForceRun telepítést; ezt nem célszerű ellenőrzés nélkül törölni.

## Ring

Ha a registryben nincs `BroadDelayDays`, a beépített alapérték 21 nap. A tényleges késleltetés és a számított `Ring eligible at` időpont a Deployer naplójában látszik.

## HPIA kilépési kódok

```text
0     sikeres
256   nincs alkalmazható ajánlás
1641  sikeres; az újraindítás elindult
3010  sikeres; újraindítás szükséges
3020  egy vagy több SoftPaq telepítése sikertelen
4098  nincs internetkapcsolat
4099  érvénytelen SoftPaq-szám
```

## Store/MSIX PowerShell megjegyzés

A rekurzív HKLM registry-törlés Microsoft Store/MSIX PowerShell 7.6.5 alatt `Requested registry access is not allowed` hibát adott, miközben Windows PowerShell 5.1 és MSI-s PowerShell 7.6.5 alatt ugyanaz a művelet működött. Hasonló registry-provider hiba esetén először ellenőrizd a tényleges `pwsh.exe` útvonalát.
