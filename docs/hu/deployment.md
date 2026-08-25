# Telepítés

## Framework install

A framework PSADT telepíti/frissíti a HP CMSL-t és HPIA-t, létrehozza a `C:\HPIA` runtime-ot, kimásolja az Automation és DriverDeployment payloadot, regisztrálja a Scheduled Taskot és létrehozza az application detection key-t.

A telepítés önmagában **nem engedélyezi** a normál evaluationt/deploymentet; a built-in Enabled defaultok False értékűek.

## Scheduled Task

```text
HP Driver Compliance Framework
SYSTEM / Highest
Any user logon + 3 perc
```

Actionök: DriverEvaluator, majd DriverDeployer.

## Rollout példa

Broad built-in:

```text
Evaluation: harmadik szerda, catch-up nélkül
Deployment: Broad, +21 nap
```

Tipikus Pilot override:

```text
Evaluation: első és harmadik szerda, catch-up bekapcsolva
Deployment: Pilot, azonnali
```

A framework és a DriverDeployer külön explicit engedélyezést igényel.

## Interaktív driver deployment

Normal/ForceRun esetén a DriverDeployer a dedikált DriverDeployment PSADT-t indítja. Ez kezeli a user prompt/defer lifecycle-t és az SPList-alapú HPIA telepítést. A jelenlegi package három defer lehetőséget ad.

Persistált PSADT defer state esetén egy későbbi DriverDeployer futás előbb ezt resume-olja, és csak utána foglalkozna új snapshottal.

## Repair

Szükség szerint frissíti a CMSL/HPIA-t, újramásolja a runtime payloadot és újraregisztrálja a Scheduled Task definícióját.

## Uninstall

Eltávolítja a Scheduled Taskot, a HP-DCF runtime-ot és a teljes framework konfigurációs registry tree-t, majd a detection key-t. A registry tree törlés rekurzív és post-condition ellenőrzött; megmaradt tree esetén az uninstall hibával zár, nem hamis success-szel.

## Verziózás

v1.0.0:

```text
Framework       1.0.0
DriverEvaluator 1.0.0
DriverDeployer  1.0.0
```
