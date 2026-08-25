# DriverDeployer

## Cél

A `DriverDeployer.ps1` a HP-DCF rollout eligibility, deferred-resume és deployment-handoff komponense.

```text
C:\HPIA\Automation\DriverDeployer.ps1
```

Normal/`-ForceRun` esetén a dedikált DriverDeployment PSADT-t indítja. `-ForceAll` esetén PSADT nélkül közvetlenül HPIA-t futtat.

## Normal végrehajtás

1. Framework/Deployer konfiguráció beolvasása.
2. Framework és DriverDeployer `Enabled=1` megkövetelése.
3. Persistált PSADT defer state vizsgálata; a deferred resume elsőbbséget élvez az új snapshot kiválasztásával szemben.
4. Feloldatlan `Deployment.active` mellett nincs új handoff.
5. Legfrissebb teljes Evaluation snapshot kiválasztása.
6. 0 recommendation esetén `NoRecommendations`.
7. Pilot/Broad eligibility.
8. Aktuális `ExcludeSoftPaqs` újraalkalmazása.
9. Globális PSADT busy ellenőrzés.
10. HP connectivity preflight.
11. Deployment handoff + ownership létrehozása.
12. DriverDeployment PSADT indítása.

## Ringek

```text
Ring           = Broad
BroadDelayDays = 21
```

Pilot azonnali. Broad eligibility = snapshot timestamp + `BroadDelayDays`.

## `-ForceRun`

Valid snapshotot igényel, de megkerüli az enablementet és ring delayt. Exclusion és aktív/deferred deployment védelem megmarad.

## `-ForceAll`

Snapshot és SPList nélkül, exclusion/ring/enablement bypass-szal, PSADT nélkül közvetlen HPIA full AutoInstallable remediationt futtat. A `0`, `256`, `1641`, `3010` sikeres kimenet; `3020`, `4098`, `4099` és ismeretlen kód hiba. Siker után törli a korábbi HP-DCF snapshot/handoff és kapcsolódó DriverDeployment defer state-et.

## Deferred resume

A Deployer a telepített DriverDeployment PSADT metadata alapján meghatározza az InstallName-et és ellenőrzi:

```text
HKLM\SOFTWARE\PSAppDeployToolkit\DeferHistory\<InstallName>
```

Meglévő defer state esetén ezt folytatja új snapshot helyett. Másik aktív PSADT mellett későbbi futásra halasztja a resume-ot.

## Handoff

```text
C:\HPIA\IAReport\Deployment\Deployment.request.json
C:\HPIA\IAReport\Deployment\Deployment.splist.txt
C:\HPIA\IAReport\Deployment\Deployment.active
```

A deployment SPList a frozen snapshot SoftPaqjait tartalmazza az aktuális exclusion újraalkalmazása után. Az active marker közvetlenül PSADT launch előtt jön létre; launch failure esetén a Deployer eltávolítja.

## Connectivity preflight

Új Normal/ForceRun handoff előtt rövid HEAD kérés ellenőrzi a HP HPIA endpoint elérhetőségét. Sikertelen preflight esetén nincs handoff, egy későbbi futás újrapróbálhatja.

## Log

```text
C:\HPIA\IAReport\DriverDeployer-<ComputerName>.log
```

A végső `SUMMARY|...` tartalmazza a mode-ot, outcome-ot, reason-t, snapshot execution ID-t, effektív SoftPaq számot és durationt.
