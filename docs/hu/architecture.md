# Architektúra

A HP Driver Compliance Framework különválasztja az **evaluation**, **deployment eligibility** és **interaktív telepítés** fázisát. Így egy adott időpontban létrehozott HP recommendation set ringeken keresztül úgy telepíthető később, hogy közben ne sodródjon automatikusan újabb SoftPaq verziókra.

## Fő komponensek

- **HP CMSL** — framework setup és HPIA lifecycle.
- **HPIA** — device analysis és tényleges remediation.
- **DriverEvaluator** — list-only evaluation és snapshot producer.
- **DriverDeployer** — snapshot selection, ring/exclusion gate, defer resume és handoff.
- **DriverDeployment PSADT** — Normal/ForceRun interaktív/deferred install layer.
- **Framework PSADT** — HP-DCF install/repair/uninstall és Scheduled Task.

## Scheduled Task orchestration

```text
HP Driver Compliance Framework
SYSTEM / Highest
Any user logon + 3 perc
Multiple instances: IgnoreNew
Start when available: True
```

Szekvenciális actionök:

```text
1. DriverEvaluator.ps1
2. DriverDeployer.ps1
```

## Normal adatfolyam

```text
Logon + 3 perc
   -> DriverEvaluator
      -> eligibility
      -> HPIA Analyze/List
      -> exclusion
      -> frozen SPList + manifest + success
   -> DriverDeployer
      -> deferred resume / snapshot selection
      -> ring + exclusion + PSADT-busy + connectivity gate
      -> Deployment.* handoff
   -> DriverDeployment PSADT
      -> user prompt / defer
      -> HPIA install a frozen SPList alapján
```

## ForceAll

```text
DriverDeployer -ForceAll
   -> nincs snapshot/SPList
   -> nincs PSADT
   -> közvetlen HPIA full AutoInstallable remediation
   -> siker után korábbi snapshot/handoff/defer state cleanup
```

## Runtime struktúra

```text
C:\HPIA\
├── Automation\
├── DriverDeployment\
├── HP Image Assistant\
└── IAReport\
    ├── Snapshots\
    └── Deployment\
```

## Alapelvek

- Normal működés explicit opt-in / fail-closed.
- Evaluator nem tölt le és nem telepít SoftPaqot.
- A committed SPList frozen deployment input.
- Exclusion evaluationkor és közvetlen deployment előtt is érvényesül.
- Pilot azonnali, Broad késleltetett.
- Aktív másik PSADT mellett nincs új handoff.
- ForceAll explicit közvetlen remediation útvonal.
