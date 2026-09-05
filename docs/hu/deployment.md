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

## Interaktív drivertelepítés

Normal/ForceRun esetén a DriverDeployer a dedikált DriverDeployment PSADT-t indítja. Ez kezeli a felhasználói párbeszédet, a telepítés elhalasztását és folytatását, valamint az SPList-alapú HPIA-telepítést. A jelenlegi csomag három elhalasztási lehetőséget biztosít.

Meglévő PSADT elhalasztási állapot esetén egy későbbi DriverDeployer-futás először ezt folytatja, és csak utána foglalkozik új snapshottal.

## Javítás

Szükség szerint frissíti a CMSL-t és a HPIA-t, újramásolja a runtime fájljait, és újraregisztrálja a Scheduled Task definícióját.

## Eltávolítás

Eltávolítja a Scheduled Taskot, a HP-DCF runtime-ot és a framework teljes konfigurációs registry struktúráját, majd a detektálási registry kulcsot. A registry struktúra törlése rekurzív, és utólagos ellenőrzés igazolja a sikerét; megmaradt struktúra esetén az eltávolítás hibával zár, nem jelez tévesen sikert.

## Verziózás

v1.0.5:

```text
Framework       1.0.5
DriverEvaluator 1.0.2
DriverDeployer  1.0.3
Administrative Template  1.0.1
```
