# Quick Start

This guide provides a minimal Pilot deployment of HP Driver Compliance Framework (HP-DCF) using the normal scheduled execution path.

## Prerequisites

Before installing HP-DCF:

- run the installation with administrative rights;
- Windows Package Manager (`winget`) must be installed and operational on the target device;
- the device must be able to reach the HP services required by HP CMSL and HPIA.

HP-DCF uses Winget during framework installation and repair to install or update HP CMSL. If the required Winget package operations are unavailable, framework installation cannot complete successfully.

## 1. Install the framework

From the framework PSADT package directory, run:

```powershell
.\Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Interactive
```

The framework package installs/updates HP CMSL and HPIA, creates the `C:\HPIA` runtime, copies the automation and DriverDeployment payloads, and registers the framework Scheduled Task.

Installation alone does not enable normal scheduled evaluation or deployment.

## 2. Enable a minimal Pilot configuration

Run the following from an elevated PowerShell session:

```powershell
New-Item `
    -Path "HKLM:\SOFTWARE\HPDriverComplianceFramework" `
    -Force | Out-Null

New-ItemProperty `
    -Path "HKLM:\SOFTWARE\HPDriverComplianceFramework" `
    -Name "Enabled" `
    -PropertyType DWord `
    -Value 1 `
    -Force | Out-Null

New-Item `
    -Path "HKLM:\SOFTWARE\HPDriverComplianceFramework\DriverDeployer" `
    -Force | Out-Null

New-ItemProperty `
    -Path "HKLM:\SOFTWARE\HPDriverComplianceFramework\DriverDeployer" `
    -Name "Enabled" `
    -PropertyType DWord `
    -Value 1 `
    -Force | Out-Null

New-ItemProperty `
    -Path "HKLM:\SOFTWARE\HPDriverComplianceFramework\DriverDeployer" `
    -Name "Ring" `
    -PropertyType String `
    -Value "Pilot" `
    -Force | Out-Null
```

This enables the framework and DriverDeployer and selects the Pilot rollout ring. Other settings continue to use their built-in defaults.

## 3. Start the Pilot flow

Sign out and sign in again.

The framework Scheduled Task is triggered at user logon with a 3-minute delay. Its actions run sequentially:

```text
DriverEvaluator
      |
      v
Evaluation snapshot
      |
      v
DriverDeployer
      |
      v
Pilot deployment eligibility
      |
      v
DriverDeployment PSADT
```

The Pilot configuration allows missed evaluation occurrences to be caught up according to the built-in evaluation policy. The Pilot ring has no Broad deployment delay, so a valid newly created evaluation snapshot is immediately eligible for deployment.

## 4. Verify the evaluation before deployment

Normal Pilot deployment starts only when DriverDeployer can select a valid, complete evaluation snapshot. A complete successful snapshot consists of the matching:

```text
Evaluation-....manifest.json
Evaluation-....splist.txt
Evaluation-....success
```

Check the snapshot directory:

```text
C:\HPIA\IAReport\Snapshots
```

The `.splist.txt` file contains the frozen SoftPaq IDs selected by DriverEvaluator. If there is no valid complete snapshot/SPList, DriverDeployer does not start the Normal deployment.

The evaluation and deployment decision can also be verified in:

```text
C:\HPIA\IAReport\DriverEvaluator-<ComputerName>.log
C:\HPIA\IAReport\DriverDeployer-<ComputerName>.log
```

DriverEvaluator logs the HPIA lifecycle check and the HPIA file version used for evaluation. DriverDeployer logs snapshot selection, eligibility and the reason when no deployment is started.

## 5. What to expect

On a successful first Pilot cycle:

1. DriverEvaluator checks/updates HPIA as required.
2. HPIA performs Analyze/List.
3. DriverEvaluator commits a valid snapshot and frozen SPList.
4. DriverDeployer selects that snapshot.
5. Pilot makes the snapshot immediately deployment-eligible.
6. DriverDeployment PSADT starts the interactive/deferred installation workflow.

Normal and `-ForceRun` deployment do not update HPIA again before installing the frozen evaluation result.

For all policy values and scheduling options, see [Configuration reference](configuration.md). For package lifecycle and Scheduled Task details, see [Deployment](deployment.md).
