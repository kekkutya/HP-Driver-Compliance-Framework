# DriverEvaluator

## Cél

A `DriverEvaluator.ps1` a HP-DCF evaluation komponense. Az aktuálisan alkalmazható HP AutoInstallable ajánlásokból validált, időponthoz kötött snapshotot készít. SoftPaq binárist nem tölt le és nem telepít.

```text
C:\HPIA\Automation\DriverEvaluator.ps1
```

## Fix HPIA scope

```text
/Operation:Analyze
/Category:Drivers,Software,Firmware,Accessories
/Selection:All
/InstallType:AutoInstallable
/Action:List
/Noninteractive
/Debug
```

## Gyors no-work útvonal

Normal módban először olcsó lokális eligibility ellenőrzéseket végez. Disabled framework, nem eligible schedule vagy már létező aktuális success marker esetén minimális efforttal kilép; ilyenkor szándékosan nincs fölösleges HPIA-, hálózati-, report- vagy log I/O.

## Normal végrehajtás

1. Konfiguráció beolvasása.
2. Framework `Enabled=1` ellenőrzése.
3. Aktuális schedule occurrence meghatározása.
4. Már sikeresen teljesített occurrence kihagyása.
5. Evaluator mutex megszerzése.
6. HPIA Analyze/List.
7. Friss HPIA JSON és recommendation adatok validálása.
8. `ExcludeSoftPaqs` alkalmazása.
9. SPList és manifest commit.
10. `.success`, hiba esetén `.failed` marker.
11. Snapshot retention.

A 0 recommendationnel végződő sikeres evaluation is valid snapshot.

## `-ForceRun`

```powershell
DriverEvaluator.ps1 -ForceRun
```

Megkerüli a framework enablementet, schedule eligibilityt és az aktuális occurrence success markerét. Az exclusion lista továbbra is érvényes.

## Snapshot contract

```text
C:\HPIA\IAReport\Snapshots\Evaluation-2026-08-W3.manifest.json
C:\HPIA\IAReport\Snapshots\Evaluation-2026-08-W3.splist.txt
C:\HPIA\IAReport\Snapshots\Evaluation-2026-08-W3.success
```

Hiba marker: `Evaluation-2026-08-W3.failed`.

A teljes sikeres snapshot az egymáshoz tartozó manifest + SPList + success hármas. Az SPList lefagyasztja az evaluationkor jóváhagyott SoftPaq ID-ket; a Deployer később nem cseréli ezeket újabb ajánlásokra. `W1`, `W3`, `WL` rendre első, harmadik és utolsó occurrence. Alapértelmezetten a legutóbbi 6 snapshot-csoport marad meg.

## Log

```text
C:\HPIA\IAReport\DriverEvaluator-<ComputerName>.log
```

Teljes evaluation végén machine-readable `SUMMARY|...` sor készül. A nagyon korai no-work kilépések szándékosan nem generálnak fölösleges log I/O-t.

## Kapcsolat a DriverDeployerrel

Az Evaluator nem indítja közvetlenül a Deployert. A Scheduled Task két szekvenciális actionje végzi az orchestrationt: előbb DriverEvaluator, utána DriverDeployer.
