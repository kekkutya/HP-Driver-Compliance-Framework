<p align="center">
  <img src="res/HP_Driver_Compliance_Framework_Banner.png" alt="HP Driver Compliance Framework" width="100%">
</p>

<p align="center">
  <a href="https://learn.microsoft.com/powershell/"><img src="https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white" alt="PowerShell 5.1+"></a>
  <a href="https://www.microsoft.com/windows/"><img src="https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?logo=windows&logoColor=white" alt="Windows 10/11"></a>
  <a href="https://ftp.ext.hp.com/pub/caps-softpaq/cmit/HPIA.html"><img src="https://img.shields.io/badge/HPIA-HP%20Image%20Assistant-0096D6" alt="HP Image Assistant"></a>
  <a href="https://psappdeploytoolkit.com/"><img src="https://img.shields.io/badge/PSADT-4.1.8-2D2D2D" alt="PSAppDeployToolkit 4.1.8"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="MIT License"></a>
  <a href="https://github.com/kekkutya/HP-Driver-Compliance-Framework/releases/latest"><img src="https://img.shields.io/github/v/release/kekkutya/HP-Driver-Compliance-Framework?label=Release" alt="Latest release"></a>
</p>

# HP Driver Compliance Framework

The **HP Driver Compliance Framework (HP-DCF)** is a Windows endpoint automation framework for controlled evaluation and deployment of HP driver, software, firmware, and accessory updates.

Current baseline: **Framework 1.0.5**, **DriverEvaluator 1.0.2**, **DriverDeployer 1.0.3**.

## Design

HP-DCF separates evaluation from deployment. DriverEvaluator runs HPIA Analyze/List and commits a validated, point-in-time SoftPaq snapshot. DriverDeployer later selects that frozen snapshot, applies Pilot/Broad rollout eligibility and current exclusions, and hands eligible work to the DriverDeployment PSADT. `-ForceAll` provides a separate direct-HPIA remediation path.

```text
User logon + 3 min
      |
      v
DriverEvaluator
      |
      v
Evaluation snapshot
      |
      v
DriverDeployer
      |
      +-- Normal / ForceRun --> DriverDeployment PSADT --> HPIA
      |
      +-- ForceAll ---------> HPIA directly
```

## Main components

| Component | Role |
|---|---|
| HP CMSL | HP management and HPIA lifecycle support used by the framework installer. |
| HPIA | Device analysis and actual remediation engine. |
| DriverEvaluator | List-only evaluation and frozen snapshot producer. |
| DriverDeployer | Ring/exclusion gates, deferred-resume logic and deployment orchestration. |
| DriverDeployment PSADT | Interactive/deferred SPList-based installation for Normal/ForceRun. |
| ADMX/ADML | Enterprise policy-backed registry configuration. |

## Fail-closed configuration

Normal operation requires explicit policy opt-in. Built-in defaults are:

```text
Framework Enabled       = False
DriverDeployer Enabled  = False
Ring                    = Broad
BroadDelayDays          = 21
Evaluation              = third Wednesday, no catch-up
```

Configuration root:

```text
HKLM\SOFTWARE\HPDriverComplianceFramework
```

## Installed runtime

```text
C:\HPIA\
├── Automation\
├── DriverDeployment\
├── HP Image Assistant\
└── IAReport\
    ├── Snapshots\
    └── Deployment\
```

## Getting started

For a minimal Pilot installation and first-run walkthrough, see the [Quick Start](docs/en/quick-start.md).

## Documentation

- [Quick Start](docs/en/quick-start.md)
- [Documentation index](docs/README.md)
- [Architecture](docs/en/architecture.md)
- [Configuration reference](docs/en/configuration.md)
- [DriverEvaluator](docs/en/DriverEvaluator.md)
- [DriverDeployer](docs/en/DriverDeployer.md)
- [Deployment](docs/en/deployment.md)
- [Troubleshooting](docs/en/troubleshooting.md)
- [Magyar dokumentáció](docs/hu/README.md)

## License

Except where otherwise noted, original HP-DCF source code and documentation are licensed under the [MIT License](LICENSE).

HP-DCF includes and redistributes third-party components, including PSAppDeployToolkit and PSAppDeployToolkit.WinGet, under their respective licenses. HP Client Management Script Library (HP CMSL) and HP Image Assistant (HPIA) are obtained separately from HP-supported sources and are not redistributed by HP-DCF.

See [Third-Party Notices](NOTICE.md) for component, license, attribution, and dependency details.
