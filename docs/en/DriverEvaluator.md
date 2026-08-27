# DriverEvaluator

## Purpose

`DriverEvaluator.ps1` is the evaluation component of HP-DCF. It creates a validated point-in-time snapshot of applicable HP AutoInstallable recommendations for later deployment decisions. It never downloads or installs SoftPaq binaries.

Runtime path:

```text
C:\HPIA\Automation\DriverEvaluator.ps1
```

## Fixed HPIA scope

```text
/Operation:Analyze
/Category:Drivers,Software,Firmware,Accessories
/Selection:All
/InstallType:AutoInstallable
/Action:List
/Noninteractive
/Debug
```

## Fast no-work path

Normal execution performs inexpensive local eligibility checks first. When the framework is disabled, the schedule is not eligible, or the current occurrence already has a success marker, DriverEvaluator exits with minimal effort. Early exits intentionally avoid unnecessary HPIA, network, report and logging I/O.

## Normal execution

1. Read framework and schedule configuration.
2. Require framework `Enabled=1`.
3. Resolve the current eligible schedule occurrence.
4. Skip an occurrence already completed successfully.
5. Acquire the evaluator mutex.
6. Run HPIA Analyze/List.
7. Validate the new HPIA JSON report and recommendation data.
8. Apply `ExcludeSoftPaqs`.
9. Commit the SPList and manifest.
10. Create the `.success` marker, or `.failed` on a failed evaluation path.
11. Apply snapshot retention.

A successful evaluation with zero recommendations is still a valid snapshot.

## Scheduling

See [Configuration](configuration.md) for all values and defaults. Monthly schedules support multiple weekday occurrences through `WeeksOfMonth`, for example `1,3`, and `-1` represents the last occurrence.

`RunOnOrAfter=1` enables catch-up. If a later configured occurrence has already been reached, it supersedes an older missed occurrence.

## `-ForceRun`

```powershell
DriverEvaluator.ps1 -ForceRun
```

Bypasses framework enablement, schedule eligibility and an existing success marker for the current occurrence. `ExcludeSoftPaqs` remains enforced.

## Snapshot contract

Location:

```text
C:\HPIA\IAReport\Snapshots
```

Example:

```text
Evaluation-2026-08-W3.manifest.json
Evaluation-2026-08-W3.splist.txt
Evaluation-2026-08-W3.success
```

After a successful deployment of the snapshot, DriverDeployment adds the persistent `.deployed` completion marker. The `.deployed` marker is not required for evaluation completeness; it records that the snapshot has subsequently reached a successful or restart-required deployment result.

Failure marker:

```text
Evaluation-2026-08-W3.failed
```

A complete successful snapshot requires the matching `.manifest.json`, `.splist.txt`, and `.success` files. The SPList freezes the exact SoftPaq IDs evaluated at that point in time; DriverDeployer does not replace them with newer recommendations later.

Occurrence suffixes include `W1` (first), `W3` (third), and `WL` (last). The latest six snapshot artifact groups are retained by default, including any matching `.deployed` completion marker.

## Logging

Full evaluation log:

```text
C:\HPIA\IAReport\DriverEvaluator-<ComputerName>.log
```

A completed evaluation ends with a machine-readable `SUMMARY|...` record including component version, recommendation counts, total duration, HPIA duration and HPIA exit code.

## Relationship to DriverDeployer

DriverEvaluator does not invoke DriverDeployer. The framework Scheduled Task owns orchestration and contains two sequential actions: DriverEvaluator first, DriverDeployer second.
