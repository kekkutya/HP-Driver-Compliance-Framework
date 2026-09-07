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

For recommended Pilot population design, monitoring requirements, and `BroadDelayDays` risk tuning, see [Pilot and Broad Ring Strategy](pilot-broad-ring-strategy.md).

## Driver deployment interaction

For Normal/ForceRun work, DriverDeployer starts the dedicated DriverDeployment PSADT package. That package owns the user prompt/defer lifecycle and invokes HPIA with the deployment SPList. The current package allows three deferrals.

If PSADT defer state remains, a later DriverDeployer invocation detects it and resumes the deferred package before considering a new snapshot.

When HPIA reaches a completed failure result, DriverDeployment does not create the snapshot-specific `.deployed` marker. It removes the transient `Deployment.active`, `Deployment.request.json`, and `Deployment.splist.txt` handoff state and returns the original HPIA failure exit code. The immutable source snapshot therefore remains eligible for a later DriverDeployer retry. On retry, the current framework exclusions are re-applied and HPIA analyzes the frozen SPList again so current applicability, rather than previous per-SoftPaq process exit codes, determines what still requires remediation.

Deferred deployments and failures that occur before a final HPIA process result is available retain their existing ownership state and are not treated as completed HPIA failures.

## Repair

Repair refreshes HP CMSL/HPIA as required, recopies the runtime payload and re-registers the Scheduled Task definition.

HPIA lifecycle updates are transactional. A downloaded HPIA payload is extracted to a staging directory and its executable and release version are validated before the active HPIA instance is replaced. The existing instance is moved to a temporary backup immediately before promotion and is restored if promotion or post-promotion validation fails. An interrupted transaction with a recoverable backup is repaired automatically on the next HPIA lifecycle check.

The SoftPaq self-extracting wrapper exit code is logged for diagnostics but is not used by itself to determine extraction success. HP-DCF validates the staged `HPImageAssistant.exe` and its release version before promotion.

## Uninstall

Uninstall removes the Scheduled Task, the complete `C:\HPIA` runtime, the framework configuration tree, and the application detection key. Registry-tree removal is recursive and verified with a post-condition check; a remaining configuration tree causes uninstall failure rather than a false success.

`C:\HPIA` is the exclusive HP-DCF working root in the 1.0.x architecture. The entire directory and all of its contents, including the HP-DCF-managed portable HPIA instance, runtime state, logs, snapshots, and deployment payload, are removed during framework uninstallation. Third-party tools, scripts, and administrative workflows must therefore not store persistent data under `C:\HPIA` or depend on binaries at this path remaining available after HP-DCF is uninstalled.

HP CMSL is treated as a shared prerequisite. HP-DCF may install or update HP CMSL during installation and repair, but intentionally leaves it installed when the framework is uninstalled because other management workflows may depend on it.

Configuration root:

```text
HKLM\SOFTWARE\HPDriverComplianceFramework
```

Detection key:

```text
HKLM\SOFTWARE\InstalledApps\HPDriverComplianceFramework
```

## Release versioning

`version.json` independently tracks framework and component versions. For v1.0.7:

```text
Framework       1.0.7
DriverEvaluator 1.0.4
DriverDeployer  1.0.5
Administrative Template  1.0.1
```

The release workflow injects component-version placeholders and validates PowerShell syntax before packaging.
