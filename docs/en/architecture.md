# Architecture

## Overview

HP Driver Compliance Framework (HP-DCF) separates **evaluation**, **deployment eligibility**, and **interactive installation** so that a point-in-time HP recommendation set can be staged through enterprise rollout rings without silently drifting to newer SoftPaq versions.

## Components

- **HP CMSL** — installed/maintained by the framework package and used for HP management/HPIA lifecycle operations.
- **HPIA** — analyzes the device and performs actual remediation.
- **DriverEvaluator** — HPIA lifecycle check, list-only evaluation and snapshot producer.
- **DriverDeployer** — snapshot selection, ring/exclusion gates, defer resume and handoff orchestration.
- **DriverDeployment PSADT** — interactive/deferred Normal/ForceRun installation layer.
- **Framework PSADT** — installs/repairs/uninstalls the HP-DCF runtime and Scheduled Task.

## Scheduled orchestration

The installer registers one task:

```text
Name: HP Driver Compliance Framework
Principal: SYSTEM
Run level: Highest
Trigger: Any user logon
Delay: 3 minutes
Multiple instances: IgnoreNew
Start when available: True
Battery start: Allowed
Stop on battery transition: False
```

Actions execute sequentially:

```text
1. powershell.exe ... C:\HPIA\Automation\DriverEvaluator.ps1
2. powershell.exe ... C:\HPIA\Automation\DriverDeployer.ps1
```

## Normal data flow

```text
User logon + 3 min
        |
        v
DriverEvaluator
  eligibility / occurrence gate
        |
        +-- eligible --> HPIA release check/update
                         |
                         v
                       HPIA Analyze/List
                         |
                         +-- exclusions
                         +-- frozen SPList
                         +-- manifest
                         +-- success marker
        |
        v
DriverDeployer
  deferred-resume check
  snapshot selection
  ring gate
  exclusion re-check
  PSADT-busy / connectivity gate
        |
        v
Deployment.request.json
Deployment.splist.txt
Deployment.active
        |
        v
DriverDeployment PSADT
  user prompt / defer
        |
        v
HPIA install using frozen SPList
        |
        +-- success/restart --> snapshot-specific .deployed marker
```

Normal/ForceRun deployment does not perform another HPIA update. The frozen evaluation result remains the deployment input.

## ForceAll path

```text
DriverDeployer -ForceAll
        |
        +-- no Evaluation snapshot or snapshot SPList
        +-- no PSADT
        +-- ExcludeSoftPaqs bypassed
        v
HPIA release check/update
        |
        v
Analyze/List AutoInstallable preflight
        |
        +-- generic OS reference (4104) --> fail closed, no remediation
        |
        +-- explicit SSMCompliant=True recommendations only
        |
        v
Transient frozen ForceAll SPList
        |
        +-- no deployable recommendations --> success, no remediation
        |
        v
HPIA install from validated ForceAll SPList
        |
        +-- success --> clear stale HP-DCF snapshot/handoff/defer state
```

## Runtime layout

```text
C:\HPIA\
├── Automation\
│   ├── DriverEvaluator.ps1
│   └── DriverDeployer.ps1
├── DriverDeployment\
├── HP Image Assistant\
└── IAReport\
    ├── Snapshots\
    └── Deployment\
```

## State ownership

Evaluation state belongs to DriverEvaluator under `IAReport\Snapshots`. The snapshot-specific `.deployed` completion marker is written by DriverDeployment after a successful/restart deployment result and retained with the corresponding snapshot. Deployment handoff state belongs to the DriverDeployer/DriverDeployment workflow under `IAReport\Deployment`. Persisted interactive defer state belongs to PSADT under its `DeferHistory` registry namespace.

## Design invariants

- Normal execution is explicit opt-in / fail-closed.
- DriverEvaluator never downloads or installs recommendation SoftPaq binaries; HPIA lifecycle maintenance may download and extract the HPIA SoftPaq.
- DriverEvaluator verifies/updates HPIA immediately before actual evaluation; Normal/ForceRun deployment does not update HPIA again.
- DriverEvaluator defensively validates HPIA AutoInstallable results and commits only recommendations with explicit `SSMCompliant=True`. Non-SSM-compliant or indeterminate recommendations are excluded from the snapshot and retained as diagnostic metadata.
- DriverEvaluator treats HPIA exit code `4104` as a fail-closed generic OS reference condition. Recommendations produced without a supported platform/OS reference are not committed to a deployment snapshot; the failed occurrence remains retryable so a later evaluation can succeed when HP publishes a supported reference.
- A committed SPList is a frozen deployment input.
- A matching `.deployed` marker makes the snapshot idempotent for later Normal executions.
- Exclusions are enforced at evaluation and immediately before Normal/ForceRun deployment.
- Pilot is immediate; Broad is delayed from the snapshot timestamp.
- New deployment handoff is not created while another PSADT deployment is active.
- ForceAll is an explicit emergency/direct-remediation path that verifies/updates HPIA and performs a fail-closed Analyze/List preflight before remediation. It bypasses Evaluation snapshots, ring eligibility, exclusions and PSADT interaction, but installs only recommendations validated with a supported platform/OS reference and explicit `SSMCompliant=True` through its transient frozen SPList.
