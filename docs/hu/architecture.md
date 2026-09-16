# Architektúra

A HP Driver Compliance Framework különválasztja a **kiértékelés**, a **telepítési jogosultság** és az **interaktív telepítés** fázisát. Így egy adott időpontban létrehozott HP-ajánlások készlete ringeken keresztül később úgy telepíthető, hogy közben ne sodródjon automatikusan újabb SoftPaq-verziókra.

## Fő komponensek

- **HP CMSL** — a framework telepítése és a HPIA életciklus-kezelése.
- **HPIA** — eszközelemzés és tényleges helyreállítás.
- **DriverEvaluator** — HPIA életciklus-ellenőrzés, csak listázást végző kiértékelés és snapshot létrehozása.
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
      -> HPIA release ellenőrzés / szükség esetén frissítés
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
      -> siker/újraindítás után snapshot-specifikus .deployed marker
```

## ForceAll

```text
DriverDeployer -ForceAll
   -> nincs Evaluation snapshot vagy snapshot SPList
   -> nincs PSADT
   -> ExcludeSoftPaqs bypass
   -> HPIA release ellenőrzés / szükség esetén frissítés
   -> Analyze/List AutoInstallable preflight
      -> generic OS reference (4104): fail-closed, nincs remediation
      -> csak explicit SSMCompliant=True recommendation
   -> transient, rögzített ForceAll SPList
      -> nincs telepíthető recommendation: siker, nincs remediation
   -> HPIA telepítés a validált ForceAll SPList alapján
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
- Az Evaluator nem tölt le és nem telepít ajánlási SoftPaqot; a HPIA életciklus-kezelése szükség esetén letöltheti és kibonthatja a HPIA SoftPaqot.
- Az Evaluator a tényleges kiértékelés előtt ellenőrzi/frissíti a HPIA-t; Normal/ForceRun deployment előtt nincs új HPIA-frissítés.
- Az Evaluator védekező módon validálja a HPIA AutoInstallable eredményét, és csak explicit `SSMCompliant=True` recommendation kerülhet a snapshotba. A nem SSM-compliant vagy nem egyértelmű recommendation kimarad a snapshotból, és diagnosztikai metadataként megmarad.
- Az Evaluator a HPIA `4104` exit kódját fail-closed generic OS reference állapotként kezeli. Támogatott platform/OS reference nélkül létrejött recommendation nem kerül deployment snapshotba; a sikertelen occurrence újrapróbálható marad, így egy későbbi kiértékelés sikeres lehet, amikor a HP már támogatott reference-t publikál.
- A rögzített SPList a telepítés változatlan bemenete.
- Az egyező `.deployed` marker biztosítja, hogy a snapshotot a későbbi Normal futások ne telepítsék újra.
- A kizárás a kiértékeléskor és közvetlenül a telepítés előtt is érvényesül.
- A Pilot azonnali, a Broad késleltetett.
- Másik aktív PSADT mellett nincs új átadás.
- A ForceAll explicit, közvetlen helyreállítási útvonal, amely a remediation előtt HPIA aktualitás-ellenőrzést és fail-closed Analyze/List preflightot végez. Az Evaluation snapshotot, a ring jogosultságot, a kizárásokat és a PSADT-t bypassolja, de csak támogatott platform/OS reference-ből származó, explicit `SSMCompliant=True` recommendation telepíthető a transient, rögzített ForceAll SPListből.
