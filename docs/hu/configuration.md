# Konfigurációs referencia

Ez a dokumentum a HP-DCF v1.0.0 effektív konfigurációs modelljét írja le.

## Precedencia és fail-closed alapértékek

Az érvényes registry/enterprise policy értékek felülírják a komponensek megfelelő beépített alapértékeit. Hiányzó értéknél a built-in default érvényesül.

A normál működés szándékosan fail-closed:

```text
Framework Enabled       = False
DriverDeployer Enabled  = False
```

A HP-DCF telepítése önmagában tehát nem engedélyezi sem az evaluationt, sem a deploymentet.

## Framework beállítások

```text
HKLM\SOFTWARE\HPDriverComplianceFramework
```

| Érték | Típus | Built-in default | Jelentés |
|---|---|---:|---|
| `Enabled` | `REG_DWORD` | `0` / False | Globális normal-execution kapcsoló. Érvényes: `0`, `1`. |
| `ExcludeSoftPaqs` | `REG_SZ` | üres | Vesszővel elválasztott numerikus SoftPaq ID-k `sp` prefix nélkül, pl. `173791,174001`. |

Az `ExcludeSoftPaqs` két ponton érvényesül: a DriverEvaluator snapshot commit előtt kiszűri ezeket, a DriverDeployer pedig Normal/`-ForceRun` deployment előtt újra alkalmazza az aktuális listát. Így egy már lefagyasztott snapshot SoftPaqja később is blokkolható. A `-ForceAll` szándékosan megkerüli az exclusion listát.

## DriverEvaluator beállítások

```text
HKLM\SOFTWARE\HPDriverComplianceFramework\DriverEvaluator
```

| Érték | Típus | Built-in default | Érvényes érték / jelentés |
|---|---|---|---|
| `ScheduleMode` | `REG_SZ` | `Monthly` | `Monthly` vagy `Weekly`. |
| `MonthMode` | `REG_SZ` | `All` | `All`, `Even`, `Odd`, `Specific`. |
| `SpecificMonths` | `REG_SZ` | üres | Hónapok `1..12`, vesszővel elválasztva; `MonthMode=Specific` mellett. |
| `WeeksOfMonth` | `REG_SZ` | `3` | Havi weekday occurrence lista `1..5`; `-1` = utolsó. |
| `WeekParity` | `REG_SZ` | `All` | Heti szűrés: `All`, `Even`, `Odd`. |
| `DayOfWeek` | `REG_SZ` | `Wednesday` | `Monday` ... `Sunday`. |
| `RunOnOrAfter` | `REG_DWORD` | `0` / False | Catch-up engedélyezése a célidőpont után. |

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

Tipikus Pilot override:

```text
WeeksOfMonth = 1,3
DayOfWeek    = Wednesday
RunOnOrAfter = 1
```

Több havi occurrence esetén a snapshot occurrence-specifikus (`W1`, `W3`, `WL`). Catch-up mellett egy már elért újabb occurrence felülírja a régebbi elmulasztott occurrence-t.

## DriverDeployer beállítások

```text
HKLM\SOFTWARE\HPDriverComplianceFramework\DriverDeployer
```

| Érték | Típus | Built-in default | Jelentés |
|---|---|---|---|
| `Enabled` | `REG_DWORD` | `0` / False | Normal DriverDeployer futás engedélyezése. |
| `Ring` | `REG_SZ` | `Broad` | `Pilot` vagy `Broad`. |
| `BroadDelayDays` | `REG_DWORD` | `21` | Broad késleltetés napokban, `0..365`. |

Pilot esetén a snapshot azonnal deploy-eligible. Broad esetén:

```text
snapshot Timestamp + BroadDelayDays
```

A deployment executable/argumentumok, HP connectivity probe, ForceAll HPIA parancs és snapshot retention v1.0.0-ben implementációs konstansok, nem policy beállítások.

## Parancssori override-ok

```powershell
DriverEvaluator.ps1 -ForceRun
DriverDeployer.ps1 -ForceRun
DriverDeployer.ps1 -ForceAll
```

Evaluator `-ForceRun`: megkerüli a framework enablementet, schedule eligibilityt és az aktuális occurrence success markerét; exclusion továbbra is él.

Deployer `-ForceRun`: valid snapshotot használ, megkerüli az enablementet és ring delayt; exclusion és deployment ownership/defer védelem továbbra is él.

Deployer `-ForceAll`: snapshot és exclusion nélkül, PSADT bypass-szal közvetlen HPIA full AutoInstallable remediationt futtat. `-ForceRun` és `-ForceAll` nem kombinálható.

## Detection key

```text
HKLM\SOFTWARE\InstalledApps\HPDriverComplianceFramework
```

Ez nem része a framework policy/configuration tree-nek.

## Administrative Templates

```text
src\ADMX\
├── HPDriverComplianceFramework.admx
├── en-US\HPDriverComplianceFramework.adml
└── hu-HU\HPDriverComplianceFramework.adml
```

A jelenlegi ADMX a fenti framework enable/exclusion, Evaluator schedule és Deployer enable/ring/Broad-delay beállításokat teszi elérhetővé.
