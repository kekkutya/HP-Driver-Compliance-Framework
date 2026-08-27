# DriverDeployer

## Cél

A `DriverDeployer.ps1` a HP-DCF rollout jogosultságát kezelő, elhalasztott telepítést folytató és telepítési átadást végző komponense.

```text
C:\HPIA\Automation\DriverDeployer.ps1
```

Normal/`-ForceRun` esetén a dedikált DriverDeployment PSADT-t indítja. `-ForceAll` esetén PSADT nélkül közvetlenül HPIA-t futtat.

## Normal végrehajtás

1. Framework/Deployer konfiguráció beolvasása.
2. Framework és DriverDeployer `Enabled=1` megkövetelése.
3. A megőrzött PSADT elhalasztási állapot vizsgálata; ha az átadáshoz tartozó snapshot már telepített, az elavult állapot törlődik, egyébként az elhalasztott telepítés folytatása elsőbbséget élvez az új snapshot kiválasztásával szemben.
4. Feloldatlan `Deployment.active` mellett nincs új átadás.
5. Legfrissebb teljes Evaluation snapshot kiválasztása; egyező `.deployed` completion marker esetén `AlreadyDeployed` eredménnyel nincs új telepítés.
6. 0 ajánlás esetén `NoRecommendations`.
7. Pilot/Broad jogosultság.
8. Aktuális `ExcludeSoftPaqs` újraalkalmazása.
9. Másik aktív PSADT ellenőrzése.
10. A HP-kapcsolat előzetes ellenőrzése.
11. A telepítési átadás és foglalás létrehozása.
12. DriverDeployment PSADT indítása.

## Ringek

```text
Ring           = Broad
BroadDelayDays = 21
```

A Pilot azonnal telepítésre jogosult, és a `BroadDelayDays` értékét figyelmen kívül hagyja. A Broad telepítési jogosultsága = snapshot időbélyege + `BroadDelayDays`.

## `-ForceRun`

Érvényes snapshotot igényel, de megkerüli az engedélyezést és a ring szerinti késleltetést. A kizárás, valamint az aktív és elhalasztott telepítések védelme megmarad.

## `-ForceAll`

Snapshot és SPList nélkül, a kizárás, a ring és az engedélyezés megkerülésével, PSADT nélkül közvetlen HPIA full AutoInstallable helyreállítást futtat. A `0`, `256`, `1641`, `3010` sikeres kimenet; a `3020`, `4098`, `4099` és az ismeretlen kód hibát jelent. Siker után törli a korábbi HP-DCF snapshot- és átadási állapotot, valamint a kapcsolódó DriverDeployment elhalasztási állapotát.

## Elhalasztott telepítés folytatása

A Deployer a telepített DriverDeployment PSADT metaadatai alapján meghatározza az InstallName értékét, és ellenőrzi:

```text
HKLM\SOFTWARE\PSAppDeployToolkit\DeferHistory\<InstallName>
```

Meglévő elhalasztási állapot esetén a Deployer először ellenőrzi, hogy a megőrzött átadás olyan snapshotra mutat-e, amelyhez már tartozik egyező `.deployed` completion marker. Az ilyen állapot elavult, ezért `AlreadyDeployed` eredménnyel eltávolításra kerül. Egyébként az elhalasztott telepítés folytatása elsőbbséget élvez az új snapshot kiválasztásával szemben. Másik aktív PSADT mellett a folytatást egy későbbi futásra halasztja.

## Telepítési átadás

```text
C:\HPIA\IAReport\Deployment\Deployment.request.json
C:\HPIA\IAReport\Deployment\Deployment.splist.txt
C:\HPIA\IAReport\Deployment\Deployment.active
```

A telepítési SPList a rögzített snapshot SoftPaqjait tartalmazza az aktuális kizárás újbóli alkalmazása után. A `Deployment.active` jelzőfájl közvetlenül a PSADT indítása előtt jön létre; indítási hiba esetén a Deployer eltávolítja. Sikeres vagy újraindítást igénylő végállapot után a DriverDeployment először létrehozza a snapshothoz tartozó tartós `.deployed` completion markert, majd eltávolítja a tranzakciós átadási fájlokat. Elhalasztás esetén az átadási és PSADT defer állapot megmarad a későbbi folytatáshoz.

## Kapcsolat előzetes ellenőrzése

Új Normal/ForceRun átadás előtt egy rövid HEAD kérés ellenőrzi a HP HPIA végpont elérhetőségét. Sikertelen előzetes ellenőrzés esetén nincs átadás; egy későbbi futás újrapróbálhatja.

## Log

```text
C:\HPIA\IAReport\DriverDeployer-<ComputerName>.log
```

A végső `SUMMARY|...` tartalmazza a módot, az eredményt, az okot, a snapshot végrehajtási azonosítóját, a ténylegesen telepítendő SoftPaqok számát és a futási időt.
