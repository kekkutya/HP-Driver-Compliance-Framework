# Telepítés

## Előfeltételek

A célgépen a Windows Package Managernek (`winget`) telepítve és működőképes állapotban kell lennie. A HP-DCF a framework telepítése és javítása során Wingetet használ a HP CMSL telepítéséhez vagy frissítéséhez. Ha a szükséges Winget csomagműveletek nem érhetők el, a framework telepítése nem tud sikeresen befejeződni.

A célgépnek el kell érnie a HP CMSL és HPIA működéséhez szükséges HP szolgáltatásokat is.

## Framework telepítése

A framework PSADT telepíti vagy frissíti a HP CMSL-t és a HPIA-t, létrehozza a `C:\HPIA` runtime-ot, kimásolja az Automation és DriverDeployment fájljait, regisztrálja a Scheduled Taskot, és létrehozza az alkalmazás detektálási registry kulcsát.

A telepítés önmagában **nem engedélyezi** a normál kiértékelést vagy telepítést; az `Enabled` beépített alapértékei `False` értékűek.

Minimális Pilot üzembe helyezéshez lásd a [Gyors üzembe helyezés](quick-start.md) dokumentumot.

## Scheduled Task

```text
HP Driver Compliance Framework
SYSTEM / Highest
Any user logon + 3 perc
```

Műveletek: DriverEvaluator, majd DriverDeployer.

## Rollout példa

Beépített Broad alapbeállítások:

```text
Kiértékelés: harmadik szerda, pótlás nélkül
Telepítés: Broad, +21 nap
```

Tipikus Pilot felülírás:

```text
Kiértékelés: első és harmadik szerda, pótlás engedélyezve
Telepítés: Pilot, azonnali
```

A framework és a DriverDeployer külön explicit engedélyezést igényel.

A Pilot-populáció javasolt kialakításához, a monitoring-követelményekhez és a `BroadDelayDays` kockázatalapú hangolásához lásd a [Pilot/Broad ring stratégia](pilot-broad-ring-strategy.md) dokumentumot.

## Interaktív drivertelepítés

Normal/ForceRun esetén a DriverDeployer a dedikált DriverDeployment PSADT-t indítja. Ez kezeli a felhasználói párbeszédet, a telepítés elhalasztását és folytatását, valamint az SPList-alapú HPIA-telepítést. A jelenlegi csomag három elhalasztási lehetőséget biztosít.

Meglévő PSADT elhalasztási állapot esetén egy későbbi DriverDeployer-futás először ezt folytatja, és csak utána foglalkozik új snapshottal.

Ha a HPIA befejezett hibás eredménnyel tér vissza, a DriverDeployment nem hozza létre a snapshot-specifikus `.deployed` markert. Törli az átmeneti `Deployment.active`, `Deployment.request.json` és `Deployment.splist.txt` handoff állapotot, és az eredeti HPIA hibakódot adja vissza. Az immutable forrás-snapshot így egy későbbi DriverDeployer-futás számára továbbra is újrapróbálható marad. Retry esetén az aktuális framework exclusionök ismét érvényesülnek, a HPIA pedig újraelemzi a rögzített SPListet, így az aktuális applicability dönti el, mi igényel még remediationt, nem a korábbi SoftPaq process exit kódok.

Az elhalasztott deployment, illetve a végleges HPIA process eredmény rendelkezésre állása előtt bekövetkező hiba megtartja a meglévő ownership állapotot, és nem minősül befejezett HPIA hibának.

## Javítás

Szükség szerint frissíti a CMSL-t és a HPIA-t, újramásolja a runtime fájljait, és újraregisztrálja a Scheduled Task definícióját.

A HPIA életciklus-frissítése tranzakciós módon történik. A letöltött HPIA payload először staging könyvtárba kerül kicsomagolásra, ahol a végrehajtható fájl és a release verzió ellenőrzése megtörténik az aktív HPIA példány lecserélése előtt. A meglévő példány közvetlenül a promotion előtt ideiglenes backupba kerül, és promotion vagy az azt követő validáció hibája esetén automatikusan visszaáll. Ha egy megszakadt tranzakció után helyreállítható backup marad, a következő HPIA életciklus-ellenőrzés automatikusan helyreállítja azt.

A SoftPaq önkicsomagoló wrapper exit kódja diagnosztikai céllal naplózásra kerül, de önmagában nem határozza meg a kicsomagolás sikerességét. A HP-DCF a stagingben létrejött `HPImageAssistant.exe` fájlt és annak release verzióját validálja a promotion előtt.

## Eltávolítás

Az eltávolítás törli a Scheduled Taskot, a teljes `C:\HPIA` runtime-ot, a framework teljes konfigurációs registry struktúráját és az alkalmazás detektálási registry kulcsát. A registry struktúra törlése rekurzív, és utólagos ellenőrzés igazolja a sikerét; megmaradt struktúra esetén az eltávolítás hibával zár, nem jelez tévesen sikert.

A `C:\HPIA` az 1.0.x architektúrában kizárólagosan a HP-DCF munkakönyvtára. A framework eltávolításakor a teljes könyvtár és annak minden tartalma törlődik, beleértve a HP-DCF által kezelt portable HPIA példányt, a runtime állapotot, a naplókat, a snapshotokat és a telepítési payloadot. Külső eszközök, scriptek és adminisztratív workflow-k ezért ne tároljanak tartós adatot a `C:\HPIA` alatt, és ne építsenek arra, hogy az ezen az útvonalon található binárisok a HP-DCF eltávolítása után is elérhetők maradnak.

A HP CMSL shared prerequisite-ként kezelt komponens. A HP-DCF telepítés és javítás során telepítheti vagy frissítheti a HP CMSL-t, de a framework eltávolításakor szándékosan nem távolítja el, mert más management workflow-k is használhatják.

## Verziózás

v1.0.7:

```text
Framework       1.0.7
DriverEvaluator 1.0.4
DriverDeployer  1.0.5
Administrative Template  1.0.1
```
