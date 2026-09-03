# Deployment

## Prerequisites

Windows Package Manager (`winget`) must be installed and operational on the target device. HP-DCF uses Winget during framework installation and repair to install or update HP CMSL. If the required Winget package operations are unavailable, framework installation cannot complete successfully.

The target device must also be able to reach the HP services required by HP CMSL and HPIA.

## Framework installation

The framework PSADT package:

1. installs/refreshes HP CMSL;
2. installs/updates HPIA;
3. creates the `C:\HPIA` runtime;
4. copies Automation and DriverDeployment payloads;
5. registers/refreshes the framework Scheduled Task;
6. creates the application detection key.

Installation alone does **not** enable normal evaluation or deployment. Built-in `Enabled` defaults are False.

For a minimal Pilot setup, see [Quick Start](quick-start.md).

## Scheduled Task

```text
HP Driver Compliance Framework
SYSTEM / Highest
Any user logon + 3 minutes
```

Actions:

```text
DriverEvaluator.ps1
DriverDeployer.ps1
```

The second action starts only after the first process ends.

## Enterprise rollout example

Broad defaults:

```text
Evaluation: third Wednesday, no catch-up
Deployment: Broad, +21 days
```

Typical Pilot overrides:

```text
Evaluation: first and third Wednesday, catch-up enabled
Deployment: Pilot, immediate
```

The framework and DriverDeployer must also be explicitly enabled by policy/registry.

## Driver deployment interaction

For Normal/ForceRun work, DriverDeployer starts the dedicated DriverDeployment PSADT package. That package owns the user prompt/defer lifecycle and invokes HPIA with the deployment SPList. The current package allows three deferrals.

If PSADT defer state remains, a later DriverDeployer invocation detects it and resumes the deferred package before considering a new snapshot.

## Repair

Repair refreshes HP CMSL/HPIA as required, recopies the runtime payload and re-registers the Scheduled Task definition.

## Uninstall

Uninstall removes the Scheduled Task, HP-DCF runtime and framework configuration tree, then removes the application detection key. Registry-tree removal is recursive and verified with a post-condition check; a remaining configuration tree causes uninstall failure rather than a false success.

Configuration root:

```text
HKLM\SOFTWARE\HPDriverComplianceFramework
```

Detection key:

```text
HKLM\SOFTWARE\InstalledApps\HPDriverComplianceFramework
```

## Release versioning

`version.json` independently tracks framework and component versions. For v1.0.4:

```text
Framework       1.0.4
DriverEvaluator 1.0.1
DriverDeployer  1.0.2
Administrative Template  1.0.1
```

The release workflow injects component-version placeholders and validates PowerShell syntax before packaging.
