# Architektúra

A HP Driver Compliance Framework különválasztja a **kiértékelés**, a **telepítési jogosultság** és az **interaktív telepítés** fázisát. Így egy adott időpontban létrehozott HP-ajánlások készlete ringeken keresztül később úgy telepíthető, hogy közben ne sodródjon automatikusan újabb SoftPaq-verziókra.

## Fő komponensek

- **HP CMSL** — a framework telepítése és a HPIA életciklus-kezelése.
- **HPIA** — eszközelemzés és tényleges helyreállítás.
- **DriverEvaluator** — csak listázást végző kiértékelés és snapshot létrehozása.
- **DriverDeployer** — snapshot-kiválasztás, ring- és exclusion-ellenőrzés, az elhalasztott telepítés folytatása és átadás.
- **DriverDeployment PSADT** — a Normal/ForceRun mód interaktív és elhalasztható telepítési rétege.
- **Framework PSADT** — a HP-DCF telepítése, javítása és eltávolítása, valamint a Scheduled Task kezelése.

## Scheduled Task orchestration

```text
HP Driver Compliance Framework
SYSTEM / Highest
Any user logon + 3 perc
Multiple instances: IgnoreNew
Start when available: True
```

Szekvenciális műveletek:

```text
1. DriverEvaluator.ps1
2. DriverDeployer.ps1
```

## Normal adatfolyam

```text
Logon + 3 perc
   -> DriverEvaluator
      -> jogosultság
      -> HPIA Analyze/List
      -> kizárás
      -> rögzített SPList + manifest + .success
   -> DriverDeployer
      -> elhalasztott telepítés folytatása / snapshot-kiválasztás
      -> ring + kizárás + PSADT-busy + kapcsolat-ellenőrzés
      -> Deployment.* átadás
   -> DriverDeployment PSADT
      -> felhasználói párbeszéd / elhalasztás
      -> HPIA-telepítés a rögzített SPList alapján
```

## ForceAll

```text
DriverDeployer -ForceAll
   -> nincs snapshot/SPList
   -> nincs PSADT
   -> közvetlen HPIA full AutoInstallable helyreállítás
   -> siker után a korábbi snapshot-/átadási/elhalasztási állapot tisztítása
```

## Futásidejű struktúra

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

- A Normal működés explicit engedélyezést igényel, alapértelmezetten tiltott (fail-closed).
- Evaluator nem tölt le és nem telepít SoftPaqot.
- A rögzített SPList a telepítés változatlan bemenete.
- A kizárás a kiértékeléskor és közvetlenül a telepítés előtt is érvényesül.
- A Pilot azonnali, a Broad késleltetett.
- Másik aktív PSADT mellett nincs új átadás.
- A ForceAll explicit, közvetlen helyreállítási útvonal.
