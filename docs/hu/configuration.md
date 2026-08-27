# Konfigurációs referencia

Ez a dokumentum a HP-DCF v1.0.0 effektív konfigurációs modelljét írja le.

## Precedencia és alapértelmezetten tiltott működés

Az érvényes registry- és enterprise policy-értékek felülírják a komponensek megfelelő beépített alapértékeit. Hiányzó értéknél a beépített alapérték érvényesül.

A normál működés szándékosan alapértelmezetten tiltott (fail-closed):

```text
Framework Enabled       = False
DriverDeployer Enabled  = False
```

A HP-DCF telepítése önmagában tehát nem engedélyezi sem a kiértékelést, sem a telepítést.

## Framework beállítások

```text
HKLM\SOFTWARE\HPDriverComplianceFramework
```

| Érték | Típus | Beépített alapérték | Jelentés |
|---|---|---:|---|
| `Enabled` | `REG_DWORD` | `0` / False | A normál végrehajtás globális kapcsolója. Érvényes: `0`, `1`. |
| `ExcludeSoftPaqs` | `REG_SZ` | üres | Vesszővel elválasztott numerikus SoftPaq ID-k `sp` prefix nélkül, pl. `173791,174001`. |

Az `ExcludeSoftPaqs` két ponton érvényesül: a DriverEvaluator a snapshot rögzítése előtt kiszűri ezeket, a DriverDeployer pedig Normal/`-ForceRun` telepítés előtt újra alkalmazza az aktuális listát. Így egy már rögzített snapshot SoftPaqja később is blokkolható. A `-ForceAll` szándékosan megkerüli a kizárási listát.

## DriverEvaluator beállítások

```text
HKLM\SOFTWARE\HPDriverComplianceFramework\DriverEvaluator
```

| Érték | Típus | Beépített alapérték | Érvényes érték / jelentés |
|---|---|---|---|
| `ScheduleMode` | `REG_SZ` | `Monthly` | `Monthly` vagy `Weekly`. |
| `MonthMode` | `REG_SZ` | `All` | `All`, `Even`, `Odd`, `Specific`. |
| `SpecificMonths` | `REG_SZ` | üres | Hónapok `1..12`, vesszővel elválasztva; `MonthMode=Specific` mellett. |
| `WeeksOfMonth` | `REG_SZ` | `3` | A konfigurált hétköznap hónapon belüli előfordulásai: `1..5`; `-1` = utolsó. |
| `WeekParity` | `REG_SZ` | `All` | Heti szűrés: `All`, `Even`, `Odd`. |
| `DayOfWeek` | `REG_SZ` | `Wednesday` | `Monday` ... `Sunday`. |
| `RunOnOrAfter` | `REG_DWORD` | `0` / False | Pótlás engedélyezése a célidőpont után. |

Beépített Broad kiértékelési alapbeállítások:

```text
ScheduleMode   = Monthly
MonthMode      = All
SpecificMonths = <empty>
WeeksOfMonth   = 3
WeekParity     = All
DayOfWeek      = Wednesday
RunOnOrAfter   = 0
```

Tipikus Pilot felülírás:

```text
WeeksOfMonth = 1,3
DayOfWeek    = Wednesday
RunOnOrAfter = 1
```

Több havi előfordulás esetén a snapshot az adott előforduláshoz kötött (`W1`, `W3`, `WL`). Engedélyezett pótlás mellett egy már elért újabb előfordulás felülírja a régebbi elmulasztott előfordulást.

## DriverDeployer beállítások

```text
HKLM\SOFTWARE\HPDriverComplianceFramework\DriverDeployer
```

| Érték | Típus | Beépített alapérték | Jelentés |
|---|---|---|---|
| `Enabled` | `REG_DWORD` | `0` / False | A DriverDeployer Normal módú futásának engedélyezése. |
| `Ring` | `REG_SZ` | `Broad` | `Pilot` vagy `Broad`. |
| `BroadDelayDays` | `REG_DWORD` | `21` | A Broad ring késleltetése napokban, `0..365`. Pilot ring esetén nincs hatása. |

Pilot esetén a snapshot azonnal telepítésre jogosult. Broad esetén:

```text
snapshot Timestamp + BroadDelayDays
```

A telepítési végrehajtható fájl és argumentumai, a HP kapcsolati ellenőrzése, a ForceAll HPIA-parancs és a snapshotok megőrzése a v1.0.0-ban implementációs konstansok, nem policy-beállítások.

## Parancssori felülírások

```powershell
DriverEvaluator.ps1 -ForceRun
DriverDeployer.ps1 -ForceRun
DriverDeployer.ps1 -ForceAll
```

Evaluator `-ForceRun`: megkerüli a framework engedélyezését, az ütemezési jogosultságot és az aktuális előfordulás `.success` jelzőfájlját; a kizárás továbbra is érvényesül.

Deployer `-ForceRun`: érvényes snapshotot használ, megkerüli az engedélyezést és a ring szerinti késleltetést; a kizárás, valamint az aktív és elhalasztott telepítések védelme továbbra is érvényesül.

Deployer `-ForceAll`: snapshot és kizárás nélkül, a PSADT megkerülésével közvetlen HPIA full AutoInstallable helyreállítást futtat. A `-ForceRun` és a `-ForceAll` nem kombinálható.

## Detektálási registry kulcs

```text
HKLM\SOFTWARE\InstalledApps\HPDriverComplianceFramework
```

Ez nem része a framework policy-/konfigurációs struktúrájának.

## Administrative Templates

```text
src\ADMX\
├── HPDriverComplianceFramework.admx
├── en-US\HPDriverComplianceFramework.adml
└── hu-HU\HPDriverComplianceFramework.adml
```

A jelenlegi ADMX a framework engedélyezési és kizárási, az Evaluator ütemezési, valamint a Deployer engedélyezési, ring- és Broad-késleltetési beállításait teszi elérhetővé.

Az Administrative Template policy-leírásai a könnyebb áttekinthetőség érdekében megjelenítik a megfelelő beépített alapértékeket. Ha egy policy nincs konfigurálva, nem történik registry-felülírás, és a framework a beépített alapértéket használja.
