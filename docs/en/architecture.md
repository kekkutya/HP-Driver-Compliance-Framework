# Architecture

## Overview

HP Driver Compliance Framework (HP-DCF) separates **evaluation**, **deployment eligibility**, and **interactive installation** so that a point-in-time HP recommendation set can be staged through enterprise rollout rings without silently drifting to newer SoftPaq versions.

## Components

- **HP CMSL** — installed/maintained by the framework package and used for HP management/HPIA lifecycle operations.
- **HPIA** — analyzes the device and performs actual remediation.
- **DriverEvaluator** — list-only evaluation and snapshot producer.
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
        +-- eligible --> HPIA Analyze/List
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
```

## ForceAll path

```text
DriverDeployer -ForceAll
        |
        +-- no snapshot
        +-- no SPList
        +-- no PSADT
        v
HPIA direct full AutoInstallable remediation
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

Evaluation state belongs to DriverEvaluator under `IAReport\Snapshots`. Deployment handoff state belongs to the DriverDeployer/DriverDeployment workflow under `IAReport\Deployment`. Persisted interactive defer state belongs to PSADT under its `DeferHistory` registry namespace.

## Design invariants

- Normal execution is explicit opt-in / fail-closed.
- DriverEvaluator never installs or downloads SoftPaq binaries.
- A committed SPList is a frozen deployment input.
- Exclusions are enforced at evaluation and immediately before Normal/ForceRun deployment.
- Pilot is immediate; Broad is delayed from the snapshot timestamp.
- New deployment handoff is not created while another PSADT deployment is active.
- ForceAll is an explicit emergency/direct-remediation path and intentionally bypasses snapshot, ring, exclusion and PSADT interaction.
