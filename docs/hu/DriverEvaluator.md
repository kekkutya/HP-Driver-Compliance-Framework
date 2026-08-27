# DriverEvaluator

## Cél

A `DriverEvaluator.ps1` a HP-DCF kiértékelési komponense. Az aktuálisan alkalmazható HP AutoInstallable ajánlásokból ellenőrzött, időponthoz kötött snapshotot készít. SoftPaq-binárist nem tölt le és nem telepít.

```text
C:\HPIA\Automation\DriverEvaluator.ps1
```

## HPIA elemzési hatókör

```text
/Operation:Analyze
/Category:Drivers,Software,Firmware,Accessories
/Selection:All
/InstallType:AutoInstallable
/Action:List
/Noninteractive
/Debug
```

## Gyors, művelet nélküli útvonal

Normal módban először gyors helyi jogosultsági ellenőrzéseket végez. Letiltott framework, nem jogosult ütemezés vagy már létező aktuális `.success` jelzőfájl esetén minimális erőforrás-ráfordítással kilép; ilyenkor szándékosan nincs fölösleges HPIA-, hálózati-, riport- vagy log I/O.

## Normal végrehajtás

1. Konfiguráció beolvasása.
2. Framework `Enabled=1` ellenőrzése.
3. Az aktuális ütemezési előfordulás meghatározása.
4. A már sikeresen teljesített előfordulás kihagyása.
5. Evaluator mutex megszerzése.
6. HPIA Analyze/List.
7. A friss HPIA JSON és ajánlási adatok ellenőrzése.
8. `ExcludeSoftPaqs` alkalmazása.
9. Az SPList és a manifest rögzítése.
10. `.success`, hiba esetén `.failed` jelzőfájl létrehozása.
11. Snapshotok megőrzésének kezelése.

A 0 ajánlással végződő sikeres kiértékelés is érvényes snapshot.

## `-ForceRun`

```powershell
DriverEvaluator.ps1 -ForceRun
```

Megkerüli a framework engedélyezését, az ütemezési jogosultságot és az aktuális előfordulás `.success` jelzőfájlját. A kizárási lista továbbra is érvényes.

## Snapshot struktúra

```text
C:\HPIA\IAReport\Snapshots\Evaluation-2026-08-W3.manifest.json
C:\HPIA\IAReport\Snapshots\Evaluation-2026-08-W3.splist.txt
C:\HPIA\IAReport\Snapshots\Evaluation-2026-08-W3.success
```

Hibajelző fájl: `Evaluation-2026-08-W3.failed`.

A teljes sikeres snapshot az egymáshoz tartozó manifest + SPList + `.success` hármas. Az SPList rögzíti a kiértékeléskor jóváhagyott SoftPaq ID-ket; a Deployer később nem cseréli ezeket újabb ajánlásokra. A `W1`, `W3` és `WL` rendre az első, harmadik és utolsó előfordulást jelöli. Alapértelmezetten a legutóbbi 6 snapshot-csoport marad meg.

## Log

```text
C:\HPIA\IAReport\DriverEvaluator-<ComputerName>.log
```

A teljes kiértékelés végén géppel feldolgozható `SUMMARY|...` sor készül. A nagyon korai, művelet nélküli kilépések szándékosan nem generálnak fölösleges log I/O-t.

## Kapcsolat a DriverDeployerrel

Az Evaluator nem indítja közvetlenül a Deployert. A Scheduled Task két szekvenciális művelete vezérli a folyamatot: előbb a DriverEvaluator, utána a DriverDeployer fut.
