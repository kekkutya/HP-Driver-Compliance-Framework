# Configuration Reference

This document describes the effective configuration model of HP-DCF v1.0.1.

## Precedence and fail-closed defaults

Supported registry / enterprise-policy values override matching built-in component defaults. Missing values use the built-in defaults.

Normal execution is deliberately fail-closed:

```text
Framework Enabled       = False
DriverDeployer Enabled  = False
```

Installing HP-DCF therefore does not enable evaluation or deployment by itself.

## Framework settings

Path:

```text
HKLM\SOFTWARE\HPDriverComplianceFramework
```

| Value | Type | Built-in default | Description |
|---|---|---:|---|
| `Enabled` | `REG_DWORD` | `0` / False | Global normal-execution switch. Valid values: `0`, `1`. |
| `ExcludeSoftPaqs` | `REG_SZ` | empty | Comma-separated numeric SoftPaq IDs without the `sp` prefix, for example `173791,174001`. |

`ExcludeSoftPaqs` is enforced twice: DriverEvaluator removes matching recommendations before committing the snapshot, and DriverDeployer re-applies the current list immediately before a Normal or `-ForceRun` deployment. This allows a SoftPaq that is already present in a frozen snapshot to be centrally blocked later. `-ForceAll` intentionally bypasses exclusions.

## DriverEvaluator settings

Path:

```text
HKLM\SOFTWARE\HPDriverComplianceFramework\DriverEvaluator
```

| Value | Type | Built-in default | Valid values / purpose |
|---|---|---|---|
| `ScheduleMode` | `REG_SZ` | `Monthly` | `Monthly` or `Weekly`. |
| `MonthMode` | `REG_SZ` | `All` | Monthly month filter: `All`, `Even`, `Odd`, `Specific`. |
| `SpecificMonths` | `REG_SZ` | empty | Comma-separated month numbers `1..12`; used with `MonthMode=Specific`. |
| `WeeksOfMonth` | `REG_SZ` | `3` | Comma-separated weekday occurrences `1..5`; `-1` means the last occurrence. |
| `WeekParity` | `REG_SZ` | `All` | Weekly filter: `All`, `Even`, `Odd`. |
| `DayOfWeek` | `REG_SZ` | `Wednesday` | `Monday` through `Sunday`. |
| `RunOnOrAfter` | `REG_DWORD` | `0` / False | Enables catch-up after the target occurrence/day. |

Built-in Broad evaluation policy:

```text
ScheduleMode   = Monthly
MonthMode      = All
SpecificMonths = <empty>
WeeksOfMonth   = 3
WeekParity     = All
DayOfWeek      = Wednesday
RunOnOrAfter   = 0
```

A typical Pilot override is:

```text
WeeksOfMonth = 1,3
DayOfWeek    = Wednesday
RunOnOrAfter = 1
```

When multiple monthly occurrences are configured, snapshots are occurrence-specific (`W1`, `W3`, `WL`). With catch-up enabled, a newer reached occurrence supersedes an older missed occurrence.

## DriverDeployer settings

Path:

```text
HKLM\SOFTWARE\HPDriverComplianceFramework\DriverDeployer
```

| Value | Type | Built-in default | Description |
|---|---|---|---|
| `Enabled` | `REG_DWORD` | `0` / False | Enables Normal DriverDeployer execution. Valid values: `0`, `1`. |
| `Ring` | `REG_SZ` | `Broad` | `Pilot` or `Broad`. |
| `BroadDelayDays` | `REG_DWORD` | `21` | Broad eligibility delay in days. Valid range: `0..365`. |

Pilot deployments are immediately eligible from the successful snapshot timestamp. Broad eligibility is:

```text
snapshot Timestamp + BroadDelayDays
```

The deployment executable, PSADT arguments, HP connectivity probe, HPIA ForceAll command and snapshot-retention count are implementation constants, not policy settings in v1.0.0.

## Command-line overrides

### DriverEvaluator

```powershell
DriverEvaluator.ps1 -ForceRun
```

Bypasses framework enablement, schedule eligibility and the current-occurrence success marker. Exclusions remain enforced.

### DriverDeployer

```powershell
DriverDeployer.ps1 -ForceRun
DriverDeployer.ps1 -ForceAll
```

`-ForceRun` uses a valid snapshot, bypasses framework/component enablement and ring delay, but still enforces exclusions and deployment ownership/defer protection.

`-ForceAll` ignores snapshots and exclusions, bypasses PSADT, and invokes HPIA directly with the fixed AutoInstallable remediation scope. `-ForceRun` and `-ForceAll` cannot be combined.

## Application detection key

The framework installer uses a separate application-detection key:

```text
HKLM\SOFTWARE\InstalledApps\HPDriverComplianceFramework
```

It is not part of the framework policy/configuration tree.

## Administrative Templates

Repository location:

```text
src\ADMX\
├── HPDriverComplianceFramework.admx
├── en-US\HPDriverComplianceFramework.adml
└── hu-HU\HPDriverComplianceFramework.adml
```

The current ADMX exposes the framework enable/exclusion settings, DriverEvaluator schedule settings, and DriverDeployer enable/ring/Broad-delay settings described above.

Administrative Template policy descriptions display the corresponding built-in default values for visibility. If a policy is not configured, no registry override is applied and the framework uses the built-in default.
