# DriverDeployer

## Purpose

`DriverDeployer.ps1` is the rollout eligibility, deferred-resume and deployment-handoff component of HP-DCF.

Runtime path:

```text
C:\HPIA\Automation\DriverDeployer.ps1
```

Normal and `-ForceRun` deployments hand work to:

```text
C:\HPIA\DriverDeployment\Invoke-AppDeployToolkit.exe
-DeploymentType Install -DeployMode Interactive
```

`-ForceAll` is different: it bypasses PSADT and invokes HPIA directly.

## Normal execution

1. Read framework and DriverDeployer configuration.
2. Require framework `Enabled=1` and DriverDeployer `Enabled=1`.
3. Detect persisted DriverDeployment PSADT defer state; clear it as stale if its handoff snapshot is already deployed, otherwise deferred resume takes precedence over new snapshot selection.
4. Refuse a new handoff while unresolved `Deployment.active` ownership exists.
5. Select the latest complete Evaluation snapshot and stop with `AlreadyDeployed` if it has a matching `.deployed` completion marker.
6. Stop with `NoRecommendations` if its recommendation count is zero.
7. Apply Pilot/Broad eligibility.
8. Re-apply the current `ExcludeSoftPaqs` list.
9. Ensure another PSADT deployment is not active.
10. Perform the HP connectivity preflight.
11. Create the deployment handoff and ownership state.
12. Start DriverDeployment PSADT.

## Rings

Built-in defaults:

```text
Ring           = Broad
BroadDelayDays = 21
```

Pilot is immediately eligible. Broad is eligible at the snapshot timestamp plus `BroadDelayDays`.

## `-ForceRun`

```powershell
DriverDeployer.ps1 -ForceRun
```

Requires a valid snapshot but bypasses framework/component enablement and ring delay. Current exclusions remain enforced. Existing deferred/active deployment protection is not bypassed.

## `-ForceAll`

```powershell
DriverDeployer.ps1 -ForceAll
```

`-ForceAll`:

- does not use an Evaluation snapshot or SPList;
- bypasses framework/component enablement, ring delay and `ExcludeSoftPaqs`;
- bypasses PSADT and invokes HPIA directly;
- uses the fixed Drivers/Software/Firmware/Accessories, `AutoInstallable`, `Action:Install` scope;
- treats HPIA `0`, `256`, `1641`, and `3010` as successful outcomes (the latter two are restart outcomes);
- treats `3020`, `4098`, `4099`, and unknown exit codes as failures;
- after success, clears previous HP-DCF snapshot, deployment-handoff and matching DriverDeployment PSADT defer state.

## Deferred deployment resume

DriverDeployer derives the DriverDeployment PSADT InstallName from the deployed package metadata and checks:

```text
HKLM\SOFTWARE\PSAppDeployToolkit\DeferHistory\<InstallName>
```

If defer state exists, DriverDeployer first checks whether the persisted handoff identifies a snapshot that already has a matching `.deployed` completion marker. Such state is stale and is cleared with `AlreadyDeployed`. Otherwise deferred resume takes precedence over selecting a new snapshot. If another PSADT process is active, the resume is left for a later execution; otherwise DriverDeployer starts the existing DriverDeployment package again.

## Deployment handoff

Location:

```text
C:\HPIA\IAReport\Deployment
```

Artifacts:

```text
Deployment.request.json
Deployment.splist.txt
Deployment.active
```

`Deployment.splist.txt` contains the frozen snapshot SoftPaq IDs after the current exclusion list has been re-applied. `Deployment.active` establishes ownership immediately before PSADT launch. If launch fails, DriverDeployer removes the newly created active marker.

After a final successful/restart result, DriverDeployment creates the snapshot-specific persistent `.deployed` completion marker before removing the transient handoff files. A deferred deployment keeps its persisted PSADT defer state and handoff for later resume.

## Connectivity preflight

Before creating a new Normal/ForceRun handoff, DriverDeployer performs a short HEAD request to the HP HPIA endpoint. If connectivity is unavailable, no handoff is created and a later invocation can retry.

## Logging

```text
C:\HPIA\IAReport\DriverDeployer-<ComputerName>.log
```

The final `SUMMARY|...` record includes mode, outcome, reason, selected snapshot execution ID, effective SoftPaq count and duration.
