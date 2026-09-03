# DriverEvaluator

## Cél

A `DriverEvaluator.ps1` a HP-DCF kiértékelési komponense. Az aktuálisan alkalmazható HP AutoInstallable ajánlásokból ellenőrzött, időponthoz kötött snapshotot készít. Az ajánlásokhoz tartozó SoftPaq-binárisokat nem tölti le és nem telepíti. A HPIA életciklus-kezelése azonban a kiértékelés előtt szükség esetén letöltheti és kibonthatja a HPIA SoftPaqot.

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
6. Az aktuális HPIA release ellenőrzése; szükség esetén a HPIA telepítése vagy frissítése.
7. A kiértékeléshez ténylegesen használt HPIA fájlverzió rögzítése.
8. HPIA Analyze/List.
9. A friss HPIA JSON és ajánlási adatok ellenőrzése.
10. `ExcludeSoftPaqs` alkalmazása.
11. Az SPList és a manifest rögzítése.
12. `.success`, hiba esetén `.failed` jelzőfájl létrehozása.
13. Snapshotok megőrzésének kezelése.

A HPIA aktualitás-ellenőrzése csak akkor történik meg, amikor az Evaluator a tényleges kiértékelési útvonalig jut. Ha a szükséges HP CMSL parancsok nem érhetők el, a HP update információ nem kérdezhető le, vagy a szükséges HPIA telepítés/frissítés sikertelen, a kiértékelés hibával leáll; nem folytatódik egy potenciálisan elavult HPIA-val.

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

A snapshot sikeres telepítése után a DriverDeployment létrehozza a tartós `.deployed` completion markert. A `.deployed` nem feltétele az evaluation snapshot teljességének; azt rögzíti, hogy a snapshot később sikeres vagy újraindítást igénylő telepítési végállapotot ért el.

A manifest a kiértékeléshez ténylegesen használt teljes HPIA fájlverziót is rögzíti a `HPIAVersion` mezőben.

A teljes sikeres snapshot az egymáshoz tartozó manifest + SPList + `.success` hármas. Az SPList rögzíti a kiértékeléskor jóváhagyott SoftPaq ID-ket; a Deployer később nem cseréli ezeket újabb ajánlásokra. A `W1`, `W3` és `WL` rendre az első, harmadik és utolsó előfordulást jelöli. Alapértelmezetten a legutóbbi 6 snapshot-csoport marad meg, a hozzájuk tartozó `.deployed` markerrel együtt.

## Log

```text
C:\HPIA\IAReport\DriverEvaluator-<ComputerName>.log
```

A log a HPIA aktualitás-ellenőrzésének eredményét és a kiértékeléshez ténylegesen használt teljes HPIA fájlverziót is rögzíti. A teljes kiértékelés végén géppel feldolgozható `SUMMARY|...` sor készül. A nagyon korai, művelet nélküli kilépések szándékosan nem generálnak fölösleges log I/O-t.

## Kapcsolat a DriverDeployerrel

Az Evaluator nem indítja közvetlenül a Deployert. A Scheduled Task két szekvenciális művelete vezérli a folyamatot: előbb a DriverEvaluator, utána a DriverDeployer fut.
